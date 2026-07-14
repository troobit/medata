"""Co-occurrence loss tests (segmenter-foundation task 10, design §4.3).

The pure halves — spec resolution, prior derivation, pair weights, the
reference presence-BCE, and the fail-fast contract — run torch-free (the
loss_config pattern). The criterion itself (finite gradients through
``train._build_criterion``) is torch-gated with ``importorskip`` per test, so
the rest of the module still runs without the training deps.
"""

from __future__ import annotations

import json

import pytest

import loss_config
import train  # torch-free import: heavy deps are lazy


def _co_stats(channel_count=35, split_seed=42, mapping_sha="ab" * 32,
              special_channel_indices=()):
    """Synthetic but schema-complete co_stats.v2 content: three training
    images {0, 3}, {0, 3}, {5} — classes 0 and 3 co-occur twice, class 5
    appears alone once, everything else absent. Special channels are excluded
    from the counts, mirroring ``prepare_dataset.build_co_stats``
    (Decision 20)."""
    specials = set(special_channel_indices)
    presence = [0] * channel_count
    joint = [[0] * channel_count for _ in range(channel_count)]
    for image in ({0, 3}, {0, 3}, {5}):
        classes = sorted(c for c in image if c not in specials)
        for c in classes:
            presence[c] += 1
            for k in classes:
                joint[c][k] += 1
    return {
        "schema": "co_stats.v2",
        "split_seed": split_seed,
        "class_mapping_sha256": mapping_sha,
        "channel_count": channel_count,
        "special_channel_indices": sorted(specials),
        "train_images": 3,
        "pixel_counts": {"train": [0] * channel_count},
        "presence_counts": presence,
        "joint_presence_counts": joint,
    }


# ── Spec resolution (lambda + pooling land in lineage) ──────────────────────────

def test_co_occurrence_spec_carries_lambda_and_pooling():
    spec = loss_config.resolve_loss_spec("co_occurrence")
    assert spec == {
        "loss": "co_occurrence",
        "co_lambda": loss_config.DEFAULT_CO_LAMBDA,
        "co_pooling": "max",
        "weighting": "inverse_frequency",
    }
    assert loss_config.resolve_loss_spec("co_occurrence", co_lambda=0.25)["co_lambda"] == 0.25
    # loss_train_config records the full spec — this is what train.py writes
    # into checkpoint provenance and build/lineage.json train_config.
    assert loss_config.loss_train_config(spec) == spec


# ── Priors and pair weights ─────────────────────────────────────────────────────

def test_co_occurrence_priors_are_conditional_frequencies():
    stats = _co_stats(channel_count=6)
    priors = loss_config.co_occurrence_priors(
        stats["joint_presence_counts"], stats["presence_counts"]
    )
    assert priors[0][3] == 1.0   # class 0 present in every image with class 3
    assert priors[3][0] == 1.0
    assert priors[5][0] == 0.0   # 5 never co-occurs with 0
    assert priors[0][0] == 1.0   # diagonal: P(c|c) = 1 where c appears
    assert priors[0][1] == 0.0   # class 1 never appears -> no evidence -> 0


def test_priors_reject_a_non_square_matrix():
    with pytest.raises(ValueError, match="square"):
        loss_config.co_occurrence_priors([[1, 0]], [1, 0])


def test_false_presence_weights_up_weight_implausible_classes():
    stats = _co_stats(channel_count=6)
    priors = loss_config.co_occurrence_priors(
        stats["joint_presence_counts"], stats["presence_counts"]
    )
    weights = loss_config.false_presence_weights(priors, gt_present=[3])
    assert weights[3] == 1.0                          # ground truth: never up-weighted
    assert weights[0] == 1.0                          # plausible (prior 1.0): stays 1
    assert weights[5] == 1.0 + loss_config.CO_PAIR_GAIN  # never co-occurs: full gain
    # No ground truth at all -> no prior evidence -> uniform weights.
    assert loss_config.false_presence_weights(priors, gt_present=[]) == [1.0] * 6


# ── L_co is zero when predicted presence matches ground truth ───────────────────

def test_presence_bce_is_zero_when_presence_matches_ground_truth():
    pred = [1.0, 0.0, 0.0, 1.0]
    gt = [1.0, 0.0, 0.0, 1.0]
    assert loss_config.co_presence_bce(pred, gt) == 0.0
    assert loss_config.co_presence_bce(pred, gt, weights=[2.0] * 4) == 0.0


def test_presence_bce_penalises_mismatch_and_respects_weights():
    gt = [1.0, 0.0]
    low = loss_config.co_presence_bce([0.9, 0.1], gt)
    high = loss_config.co_presence_bce([0.5, 0.5], gt)
    assert 0.0 < low < high
    weighted = loss_config.co_presence_bce([0.5, 0.5], gt, weights=[1.0, 4.0])
    assert weighted > high  # up-weighting the false presence raises the term


# ── Food-channel restriction (Decision 20) ──────────────────────────────────────

def test_food_channel_indices_drop_the_recorded_specials():
    stats = _co_stats(channel_count=6, special_channel_indices=[4, 5])
    assert loss_config.food_channel_indices(stats) == [0, 1, 2, 3]
    # No specials recorded -> every channel is a food channel.
    assert loss_config.food_channel_indices(_co_stats(channel_count=6)) == list(range(6))


# ── Fail-fast contract (design §4.3): missing and stale co_stats ────────────────

def test_missing_co_stats_fails_with_regeneration_command(tmp_path):
    with pytest.raises(SystemExit, match="prepare_dataset.py"):
        loss_config.load_co_stats(
            tmp_path / "co_stats.json", split_seed=42, class_mapping_sha256="x",
        )


def test_stale_seed_fails_with_regeneration_command(tmp_path):
    path = tmp_path / "co_stats.json"
    path.write_text(json.dumps(_co_stats(split_seed=42, mapping_sha="ab" * 32)))
    with pytest.raises(SystemExit, match=r"split seed 42.*--split-seed 7"):
        loss_config.load_co_stats(path, split_seed=7, class_mapping_sha256="ab" * 32)


def test_stale_mapping_sha_fails_with_regeneration_command(tmp_path):
    path = tmp_path / "co_stats.json"
    path.write_text(json.dumps(_co_stats(split_seed=42, mapping_sha="ab" * 32)))
    with pytest.raises(SystemExit, match="class mapping SHA-256"):
        loss_config.load_co_stats(path, split_seed=42, class_mapping_sha256="cd" * 32)


def test_v1_schema_fails_with_regeneration_command(tmp_path):
    path = tmp_path / "co_stats.json"
    stats = _co_stats(split_seed=42, mapping_sha="ab" * 32)
    stats["schema"] = "co_stats.v1"  # pre-Decision-20 file: background counted
    del stats["special_channel_indices"]
    path.write_text(json.dumps(stats))
    with pytest.raises(SystemExit, match=r"co_stats\.v1.*co_stats\.v2"):
        loss_config.load_co_stats(path, split_seed=42, class_mapping_sha256="ab" * 32)


def test_omitted_split_seed_fails(tmp_path):
    path = tmp_path / "co_stats.json"
    path.write_text(json.dumps(_co_stats()))
    with pytest.raises(SystemExit, match="--split-seed"):
        loss_config.load_co_stats(path, split_seed=None, class_mapping_sha256="ab" * 32)


def test_matching_co_stats_load_round_trips(tmp_path):
    path = tmp_path / "co_stats.json"
    stats = _co_stats(split_seed=42, mapping_sha="ab" * 32)
    path.write_text(json.dumps(stats))
    loaded = loss_config.load_co_stats(
        path, split_seed=42, class_mapping_sha256="ab" * 32
    )
    assert loaded == stats


# ── Torch criterion (gated: skipped without the training deps) ──────────────────

def test_criterion_gradients_are_finite_and_match_presence_semantics():
    torch = pytest.importorskip("torch")

    num_classes = 6
    spec = loss_config.resolve_loss_spec("co_occurrence")
    criterion = train._build_criterion(
        spec, class_weights=[1.0] * num_classes, device=torch.device("cpu"),
        co_stats=_co_stats(channel_count=num_classes),
    )
    torch.manual_seed(0)
    logits = torch.randn(2, num_classes, 8, 8, requires_grad=True)
    targets = torch.randint(0, num_classes, (2, 8, 8))
    loss = criterion(logits, targets)
    assert torch.isfinite(loss)
    loss.backward()
    assert logits.grad is not None
    assert torch.isfinite(logits.grad).all()


def test_criterion_reduces_to_weighted_ce_when_presence_matches():
    torch = pytest.importorskip("torch")
    import torch.nn as nn

    num_classes = 6
    spec = loss_config.resolve_loss_spec("co_occurrence")
    criterion = train._build_criterion(
        spec, class_weights=[1.0] * num_classes, device=torch.device("cpu"),
        co_stats=_co_stats(channel_count=num_classes),
    )
    # Saturated logits: predicted presence == ground-truth presence, so the
    # L_co term contributes (numerically) nothing beyond the clamp epsilon.
    targets = torch.zeros(1, 4, 4, dtype=torch.long)
    targets[0, :, 2:] = 3
    logits = torch.full((1, num_classes, 4, 4), -40.0)
    logits[0, 0][targets[0] == 0] = 40.0
    logits[0, 3][targets[0] == 3] = 40.0
    base = nn.CrossEntropyLoss(weight=torch.ones(num_classes))(logits, targets)
    total = criterion(logits, targets)
    assert torch.isclose(total, base, atol=1e-4)


def test_presence_term_ignores_special_channels():
    torch = pytest.importorskip("torch")

    num_classes = 6
    spec = loss_config.resolve_loss_spec("co_occurrence")

    def _criterion(specials):
        return train._build_criterion(
            spec, class_weights=[1.0] * num_classes, device=torch.device("cpu"),
            co_stats=_co_stats(
                channel_count=num_classes, special_channel_indices=specials,
            ),
        )

    # Saturated correct prediction on classes 0 and 3, plus one pixel where
    # channel 5 ties the correct class — a false presence (~0.5) of channel 5.
    targets = torch.zeros(1, 4, 4, dtype=torch.long)
    targets[0, :, 2:] = 3
    logits = torch.full((1, num_classes, 4, 4), -40.0)
    logits[0, 0][targets[0] == 0] = 40.0
    logits[0, 3][targets[0] == 3] = 40.0
    logits[0, 5, 0, 0] = 40.0

    # With channel 5 recorded as special it is outside the presence term
    # entirely (Decision 20); counted as a food channel, the same false
    # presence is penalised at full pair gain — so the loss must be larger.
    assert _criterion([5])(logits, targets) < _criterion([])(logits, targets)

#!/usr/bin/env python3
"""Loss selection + class-weight derivation for the segmenter trainer (PURE).

The PRD "Segmenter training pipeline" context adds a class-imbalance-aware loss
option to ``train.py`` behind a CLI flag (``--loss {ce,weighted_ce,focal,dice,
combined,co_occurrence}`` — the last added by segmenter-foundation design §4.3).
Under a heavily class-imbalanced 35-class palette (device masks are
92–99% background) a plain unweighted cross-entropy collapses toward the dominant
background class and the residual food pixels come through as isolated speckle —
the "stripes of spots" the PRD targets.

This module holds the parts of that recipe that are PURE ARITHMETIC / PURE
DISPATCH, so they are unit-testable WITHOUT torch installed (matching the
torch-free pattern of ``lineage.py`` / ``validation.py``). Everything here is:

  - ``resolve_loss_spec(name, ...)`` — validate the CLI ``--loss`` name and return
    a small, JSON-serialisable dict describing the chosen loss + weighting scheme.
    ``train.py`` records this verbatim in the checkpoint and ``build/lineage.json``
    ``train_config`` (Req: reproducible from lineage), and dispatches on it to
    build the actual torch ``nn`` loss behind its lazy-import boundary.
  - ``class_weights(scheme, pixel_counts, num_classes, ...)`` — per-class weight
    derivation for the ``--class-weighting`` scheme. Pure arithmetic; no torch
    tensor is constructed here — ``train.py`` wraps the returned list in a
    ``torch.tensor`` on the training device.

CLASS-WEIGHTING SCHEMES (snaq-parity Req 6.3, Decision 13): inverse-frequency
weighting was attributed as the staple-regression cause (segmenter-foundation
Decision 25) and is REMOVED from this module entirely — not defaulted away —
so it cannot be re-selected by accident. ``--class-weighting {none,
sqrt_inverse}`` (default ``none``) parameterises every weighted loss;
``sqrt_inverse`` is the deliberately milder re-test scheme (the class-weight
spread is the square root of what inverse frequency produced). ``--loss
weighted_ce --class-weighting none`` is rejected: it would be plain ``ce`` in
disguise and corrupt an opportunistic loss-sweep verdict (Req 6.5).

The DEFAULT (``ce``) reproduces today's ``nn.CrossEntropyLoss()`` byte-for-byte in
the recorded ``train_config``: for the default spec ``loss_train_config`` returns
an EMPTY provenance block, so an omitted (or explicit ``--loss ce``) flag
serialises identically to a run made before this module existed — the absence of
a ``loss`` key in checkpoint/lineage means the historical unweighted
cross-entropy.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any, Mapping, Sequence

# The CLI --loss choices. "ce" is the historical default (plain unweighted
# cross-entropy); the rest are the class-imbalance-aware options.
# "co_occurrence" (segmenter-foundation design §4.3, Decision 15) is
# L = weighted_ce + lambda * L_co, where L_co penalises image-level predicted
# class presence against ground-truth presence with co-occurrence pair weights.
LOSS_CHOICES = ("ce", "weighted_ce", "focal", "dice", "combined", "co_occurrence")
DEFAULT_LOSS = "ce"

# Losses whose CE base accepts per-class weights. "ce", "focal" (which
# down-weights easy pixels via gamma instead) and "dice" (region-overlap, already
# imbalance-robust) do not. "co_occurrence" uses them for its CE base.
WEIGHTED_LOSSES = ("weighted_ce", "combined", "co_occurrence")

# Class-weighting schemes for the weighted losses (snaq-parity Req 6.3,
# Decision 13). "none" (the default) applies no weight vector; "sqrt_inverse"
# is the deliberately milder re-test of class weighting — inverse frequency
# itself is banned (Decision 25) and deliberately absent from this tuple.
WEIGHTING_CHOICES = ("none", "sqrt_inverse")
DEFAULT_WEIGHTING = "none"

# Default focal-loss focusing parameter (Lin et al. 2017); down-weights
# well-classified pixels so the dominant background stops swamping the gradient.
DEFAULT_FOCAL_GAMMA = 2.0

# Default mixing weight for the "combined" loss: total = dice_weight * dice +
# (1 - dice_weight) * weighted_ce. 0.5 gives the CE term and the region term
# equal say (a common Dice+CE recipe).
DEFAULT_DICE_WEIGHT = 0.5

# Smoothing constant for the soft-Dice denominator (avoids /0 on absent classes).
DICE_SMOOTH = 1.0

# Cap on any single normalised class weight. A very rare class would otherwise
# get an enormous inverse-frequency weight and destabilise the gradient; 10x the
# mean is plenty of emphasis for the thin staples.
MAX_CLASS_WEIGHT = 10.0

# ── Co-occurrence loss (design §4.3, Decision 15) ───────────────────────────────

# Mixing weight for the auxiliary image-level presence term:
# L = weighted_ce + CO_LAMBDA * L_co. 0.1 keeps the image-level term
# subordinate to the pixel loss; treated as fixed for the first run and swept
# only if training logs show L_co dominating or vanishing (design §4.3).
DEFAULT_CO_LAMBDA = 0.1

# Image-level predicted presence pooling: p_c = maxpool(softmax_c) over the
# spatial dims. Log-sum-exp or top-k pooling is the noted fallback if a single
# spurious activation saturating the max proves unstable — recorded here so
# lineage's "co_pooling" value has a documented alternative set.
DEFAULT_CO_POOLING = "max"

# Gain on the pair weight for FALSE presences: a predicted-but-absent class
# whose co-occurrence prior with the image's ground-truth classes is near zero
# gets weight 1 + CO_PAIR_GAIN * (1 - prior) — up to (1 + gain)x for a
# never-co-occurring class, 1x for a fully plausible one. True presences (and
# missed ground-truth classes — the collapse half, carried by the presence-BCE
# term itself and the weighted_ce base) keep weight 1. The 3.0 keeps the
# up-weighting bounded (max 4x), in the same spirit as MAX_CLASS_WEIGHT.
CO_PAIR_GAIN = 3.0

# Name of the statistics file prepare_dataset.py writes next to splits.json.
CO_STATS_FILENAME = "co_stats.json"

# Required co_stats schema. v2 (Decision 20) restricts the presence /
# joint-presence counts to the FOOD channels and records the excluded
# ``special_channel_indices``; a v1 file (which counted background into the
# priors) must not silently feed the criterion, so load_co_stats rejects it.
CO_STATS_SCHEMA = "co_stats.v2"

# Regeneration command template for the fail-fast messages (design §4.3): a
# silent fallback to unweighted CE or stats from a different split would
# falsify the lineage's claim about the recipe.
_CO_STATS_REGENERATE = (
    "regenerate with: python tools/segmenter/prepare_dataset.py "
    "--src <foodseg103 root> "
    "--mapping tools/segmenter/class_mapping_foodseg103_v1.json "
    "--out <data root> --seed <split seed>"
)


def normalise_loss_name(name: str | None) -> str:
    """Return a validated loss name, defaulting ``None`` to ``DEFAULT_LOSS``.

    Raises ``ValueError`` on an unknown name so the CLI surfaces a clear message
    rather than silently building the wrong loss.
    """
    resolved = DEFAULT_LOSS if name is None else name
    if resolved not in LOSS_CHOICES:
        raise ValueError(
            f"unknown loss {resolved!r}; choose one of {', '.join(LOSS_CHOICES)}"
        )
    return resolved


def normalise_weighting_name(scheme: str | None) -> str:
    """Return a validated class-weighting scheme, defaulting ``None`` to
    ``DEFAULT_WEIGHTING``. Unknown schemes — including the removed
    ``inverse_frequency`` (Decision 25) — raise ``ValueError``."""
    resolved = DEFAULT_WEIGHTING if scheme is None else scheme
    if resolved not in WEIGHTING_CHOICES:
        raise ValueError(
            f"unknown class-weighting scheme {resolved!r}; choose one of "
            f"{', '.join(WEIGHTING_CHOICES)}"
        )
    return resolved


def loss_uses_class_weights(name: str, class_weighting: str | None = None) -> bool:
    """Whether this loss + scheme combination consumes a per-class weight
    vector: a weighted loss under an ACTIVE scheme. Under ``none`` no vector is
    derived — the CE base runs unweighted (snaq-parity Req 6.3)."""
    return (normalise_loss_name(name) in WEIGHTED_LOSSES
            and normalise_weighting_name(class_weighting) != "none")


def resolve_loss_spec(
    name: str | None = None,
    *,
    focal_gamma: float = DEFAULT_FOCAL_GAMMA,
    dice_weight: float = DEFAULT_DICE_WEIGHT,
    co_lambda: float = DEFAULT_CO_LAMBDA,
    class_weighting: str | None = None,
) -> dict[str, Any]:
    """Pure dispatch: map a ``--loss`` name to a JSON-serialisable loss spec.

    The spec names the loss and only the parameters that loss actually uses, so
    ``train.py`` can both (a) record it verbatim in provenance and (b) branch on
    ``spec["loss"]`` to build the torch module. Keeping the DEFAULT spec minimal
    (``{"loss": "ce"}``) is what makes an omitted flag byte-identical to a
    pre-existing run's ``train_config``. For ``co_occurrence`` the spec carries
    lambda and the pooling choice — both land in lineage (design §4.3).

    Weighted losses record the ``class_weighting`` scheme under ``weighting``.
    ``weighted_ce`` under scheme ``none`` is rejected (snaq-parity Req 6.3): it
    is plain ``ce`` in disguise and would corrupt a sweep verdict; ``combined``
    and ``co_occurrence`` keep their dice / presence terms under ``none`` and
    stay valid.
    """
    resolved = normalise_loss_name(name)
    scheme = normalise_weighting_name(class_weighting)
    spec: dict[str, Any] = {"loss": resolved}
    if resolved == "focal":
        spec["focal_gamma"] = float(focal_gamma)
    elif resolved == "combined":
        # combined = dice_weight * dice + (1 - dice_weight) * [weighted] ce
        spec["dice_weight"] = float(dice_weight)
        spec["weighting"] = scheme
    elif resolved == "weighted_ce":
        if scheme == "none":
            raise ValueError(
                "--loss weighted_ce needs an active --class-weighting scheme "
                "(sqrt_inverse): under 'none' it is plain ce in disguise and "
                "would corrupt a loss-sweep verdict (snaq-parity Req 6.3)"
            )
        spec["weighting"] = scheme
    elif resolved == "co_occurrence":
        # co_occurrence = [weighted] ce + co_lambda * L_co (design §4.3)
        spec["co_lambda"] = float(co_lambda)
        spec["co_pooling"] = DEFAULT_CO_POOLING
        spec["weighting"] = scheme
    return spec


def loss_train_config(spec: dict[str, Any]) -> dict[str, Any]:
    """The provenance block recorded under ``train_config`` for this loss.

    For the default ``ce`` this is EMPTY — an omitted ``--loss`` flag must leave
    the recorded ``train_config`` byte-for-byte identical to a run made before
    the flag existed (PRD acceptance), so the absence of a ``loss`` key means
    the historical unweighted cross-entropy. Non-default losses carry their
    parameters so a run is reproducible from lineage alone.
    """
    if spec == {"loss": DEFAULT_LOSS}:
        return {}
    return dict(spec)


def class_weights(
    scheme: str,
    pixel_counts: Sequence[float],
    num_classes: int,
    *,
    ignore_classes: Sequence[int] = (),
    eps: float = 1.0,
    max_weight: float | None = MAX_CLASS_WEIGHT,
) -> list[float] | None:
    """Per-class weights for a ``--class-weighting`` scheme (snaq-parity
    Req 6.3, Decision 13). ``None`` for scheme ``none`` — no vector at all, the
    CE base runs unweighted.

    ``sqrt_inverse`` — the deliberately milder replacement for the banned
    inverse-frequency scheme (segmenter-foundation Decision 25) — takes the
    SQUARE ROOT of the raw inverse frequency:

      weight_c = sqrt(total_pixels / (num_classes * (count_c + eps)))

    so the spread between any two classes is the square root of what inverse
    frequency produced. Then normalise so the mean weight over the KEPT classes
    is 1.0 (leaving the overall loss scale — and hence the effective learning
    rate — comparable to plain CE), and clamp each kept weight to
    ``max_weight``. ``ignore_classes`` (e.g. the non-food sentinels) are pinned
    to weight 1.0 and excluded from the normalisation mean, so they neither
    dominate nor rescale the food-class weights.

    Classes with a ZERO pixel count are pinned the same way automatically: a CE
    class weight only applies where the class appears as a target, so an
    absent-from-train class's weight is never used — but its huge raw value
    would otherwise inflate the normalisation mean and squash every real weight
    towards zero. ``eps`` (Laplace add-one by default) keeps the arithmetic
    finite regardless.

    Pure arithmetic on plain floats — ``train.py`` wraps the result in a
    ``torch.tensor`` on the training device.
    """
    if normalise_weighting_name(scheme) == "none":
        return None

    counts = [float(c) for c in pixel_counts]
    if len(counts) != num_classes:
        raise ValueError(
            f"pixel_counts has {len(counts)} entries but num_classes is {num_classes}"
        )
    if num_classes <= 0:
        raise ValueError("num_classes must be positive")
    if any(c < 0 for c in counts):
        raise ValueError("pixel_counts must be non-negative")
    if max_weight is not None and max_weight <= 0:
        raise ValueError("max_weight must be positive")

    total = sum(counts)
    if total <= 0:
        # No pixels observed at all: fall back to uniform weights.
        return [1.0] * num_classes

    # Explicitly ignored classes plus absent classes (see docstring).
    pinned = set(ignore_classes) | {c for c in range(num_classes) if counts[c] == 0}

    raw = [
        1.0 if c in pinned
        else math.sqrt(total / (num_classes * (counts[c] + eps)))
        for c in range(num_classes)
    ]

    kept = [raw[c] for c in range(num_classes) if c not in pinned]
    mean_kept = sum(kept) / len(kept) if kept else 1.0
    if mean_kept <= 0:
        return [1.0] * num_classes

    def _clamp(w: float) -> float:
        return min(w, max_weight) if max_weight is not None else w

    return [
        1.0 if c in pinned else _clamp(raw[c] / mean_kept)
        for c in range(num_classes)
    ]


# ── Co-occurrence loss helpers (design §4.3) — pure, torch-free ─────────────────

def load_co_stats(
    path: str | Path,
    *,
    split_seed: int | None,
    class_mapping_sha256: str,
) -> dict[str, Any]:
    """Load ``co_stats.json`` and enforce the fail-fast contract (design §4.3).

    The file records its schema plus the split seed and class-mapping SHA-256
    it was built from; if the file is missing, carries a schema other than
    ``CO_STATS_SCHEMA`` (a pre-Decision-20 v1 file counted background into
    the priors), or either stamped value mismatches the training
    invocation's, this raises ``SystemExit`` with the regeneration command —
    a silent fallback to unweighted CE (or stats from a different split)
    would falsify the lineage's claim about the recipe.
    """
    p = Path(path)
    if not p.is_file():
        raise SystemExit(
            f"[train] co-occurrence statistics not found: {p} — {_CO_STATS_REGENERATE}"
        )
    stats = json.loads(p.read_text(encoding="utf-8"))
    if stats.get("schema") != CO_STATS_SCHEMA:
        raise SystemExit(
            f"[train] {p} has schema {stats.get('schema')!r} but this trainer "
            f"requires {CO_STATS_SCHEMA!r} (food-channels-only presence "
            "statistics, Decision 20) — stale format; "
            f"{_CO_STATS_REGENERATE}"
        )
    if split_seed is None:
        raise SystemExit(
            "[train] --loss co_occurrence requires --split-seed (the seed the "
            f"dataset was prepared with) so {p.name} can be verified against "
            f"the invocation — {_CO_STATS_REGENERATE}"
        )
    if stats.get("split_seed") != split_seed:
        raise SystemExit(
            f"[train] {p} was built for split seed {stats.get('split_seed')!r} "
            f"but this invocation uses --split-seed {split_seed} — stale "
            f"statistics; {_CO_STATS_REGENERATE}"
        )
    if stats.get("class_mapping_sha256") != class_mapping_sha256:
        raise SystemExit(
            f"[train] {p} was built from class mapping SHA-256 "
            f"{stats.get('class_mapping_sha256')!r} but the committed mapping "
            f"hashes to {class_mapping_sha256!r} — stale statistics; "
            f"{_CO_STATS_REGENERATE}"
        )
    return stats


def food_channel_indices(co_stats: Mapping[str, Any]) -> list[int]:
    """The palette indices the co-occurrence loss operates on (Decision 20).

    Every channel minus the ``special_channel_indices`` recorded by
    ``prepare_dataset.py`` — the same special-channel exclusion
    ``validation.special_channel_names`` applies to the IoU gate. "Background
    present" is trivially true of every plate and carries no signal, and
    special-channel pixels are already supervised by the CE base, so the
    presence-BCE vectors, the ground-truth compat set, and the priors are all
    restricted to these food channels.
    """
    specials = {int(c) for c in co_stats["special_channel_indices"]}
    return [c for c in range(int(co_stats["channel_count"])) if c not in specials]


def co_occurrence_priors(
    joint_presence_counts: Sequence[Sequence[float]],
    presence_counts: Sequence[float],
) -> list[list[float]]:
    """Conditional co-occurrence priors from the co_stats counts.

    ``prior[c][k] = P(class c present | class k present)`` =
    ``joint[c][k] / presence[k]`` — in [0, 1], with 0 when class ``k`` never
    appears in training (no evidence either way, so a false presence alongside
    it gets the full up-weight). The diagonal is 1 wherever the class appears.
    Pure arithmetic on plain floats; ``train.py`` wraps the result in a torch
    tensor.
    """
    n = len(presence_counts)
    if any(len(row) != n for row in joint_presence_counts) or len(joint_presence_counts) != n:
        raise ValueError("joint_presence_counts must be square and match presence_counts")
    return [
        [
            (float(joint_presence_counts[c][k]) / float(presence_counts[k]))
            if presence_counts[k] > 0 else 0.0
            for k in range(n)
        ]
        for c in range(n)
    ]


def false_presence_weights(
    priors: Sequence[Sequence[float]],
    gt_present: Sequence[int],
    *,
    gain: float = CO_PAIR_GAIN,
) -> list[float]:
    """Per-class pair weights for one image's presence-BCE term (design §4.3).

    Classes IN the ground truth keep weight 1.0 (a missed ground-truth class —
    the collapse half — is penalised by the BCE term itself, not the pair
    weight). Classes NOT in the ground truth are weighted
    ``1 + gain * (1 - compat)`` where ``compat`` is the largest co-occurrence
    prior between the class and any ground-truth class — so an implausible
    false presence (prior near zero) is up-weighted toward ``1 + gain`` and a
    plausible one stays near 1. With no ground-truth classes at all, every
    weight is 1 (no prior evidence to weight by).
    """
    n = len(priors)
    gt = set(gt_present)
    if not gt:
        return [1.0] * n
    weights = []
    for c in range(n):
        if c in gt:
            weights.append(1.0)
        else:
            compat = max(float(priors[c][k]) for k in gt)
            weights.append(1.0 + gain * (1.0 - compat))
    return weights


def co_presence_bce(
    pred_presence: Sequence[float],
    gt_presence: Sequence[float],
    weights: Sequence[float] | None = None,
) -> float:
    """Reference (pure-float) presence BCE for one image: the ``L_co`` term.

    Mean over classes of ``w_c * BCE(p_c, y_c)``. Exactly zero when predicted
    presence matches the ground truth (p == y at 0/1), matching the torch
    implementation in ``train._build_criterion``. Used by the torch-free tests;
    the training loop computes the same quantity with tensors.
    """
    n = len(pred_presence)
    if len(gt_presence) != n or (weights is not None and len(weights) != n):
        raise ValueError("pred/gt/weights must have equal length")
    eps = 1e-12
    total = 0.0
    for c in range(n):
        p = min(max(float(pred_presence[c]), 0.0), 1.0)
        y = float(gt_presence[c])
        w = 1.0 if weights is None else float(weights[c])
        bce = -math.log(max(p, eps)) if y >= 0.5 else -math.log(max(1.0 - p, eps))
        total += w * bce
    return total / n if n else 0.0

#!/usr/bin/env python3
"""Loss selection + class-weight derivation for the segmenter trainer (PURE).

The PRD "Segmenter training pipeline" context adds a class-imbalance-aware loss
option to ``train.py`` behind a CLI flag (``--loss {ce,weighted_ce,focal,dice,
combined}``). Under a heavily class-imbalanced 35-class palette (device masks are
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
  - ``inverse_frequency_weights(pixel_counts, num_classes, ...)`` — normalised
    inverse-frequency class weights from per-class pixel counts. Pure arithmetic;
    no torch tensor is constructed here — ``train.py`` wraps the returned list in a
    ``torch.tensor`` on the training device.

The DEFAULT (``ce``) reproduces today's ``nn.CrossEntropyLoss()`` byte-for-byte in
the recorded ``train_config``: for the default spec ``loss_train_config`` returns
an EMPTY provenance block, so an omitted (or explicit ``--loss ce``) flag
serialises identically to a run made before this module existed — the absence of
a ``loss`` key in checkpoint/lineage means the historical unweighted
cross-entropy.
"""

from __future__ import annotations

from typing import Any, Sequence

# The CLI --loss choices. "ce" is the historical default (plain unweighted
# cross-entropy); the rest are the class-imbalance-aware options.
LOSS_CHOICES = ("ce", "weighted_ce", "focal", "dice", "combined")
DEFAULT_LOSS = "ce"

# Losses that consume per-class inverse-frequency weights. "ce", "focal" (which
# down-weights easy pixels via gamma instead) and "dice" (region-overlap, already
# imbalance-robust) do not.
WEIGHTED_LOSSES = ("weighted_ce", "combined")

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


def loss_uses_class_weights(name: str) -> bool:
    """Whether the named loss consumes per-class inverse-frequency weights."""
    return normalise_loss_name(name) in WEIGHTED_LOSSES


def resolve_loss_spec(
    name: str | None = None,
    *,
    focal_gamma: float = DEFAULT_FOCAL_GAMMA,
    dice_weight: float = DEFAULT_DICE_WEIGHT,
) -> dict[str, Any]:
    """Pure dispatch: map a ``--loss`` name to a JSON-serialisable loss spec.

    The spec names the loss and only the parameters that loss actually uses, so
    ``train.py`` can both (a) record it verbatim in provenance and (b) branch on
    ``spec["loss"]`` to build the torch module. Keeping the DEFAULT spec minimal
    (``{"loss": "ce"}``) is what makes an omitted flag byte-identical to a
    pre-existing run's ``train_config``.
    """
    resolved = normalise_loss_name(name)
    spec: dict[str, Any] = {"loss": resolved}
    if resolved == "focal":
        spec["focal_gamma"] = float(focal_gamma)
    elif resolved == "combined":
        # combined = dice_weight * dice + (1 - dice_weight) * weighted_ce
        spec["dice_weight"] = float(dice_weight)
        spec["weighting"] = "inverse_frequency"
    elif resolved == "weighted_ce":
        spec["weighting"] = "inverse_frequency"
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


def inverse_frequency_weights(
    pixel_counts: Sequence[float],
    num_classes: int,
    *,
    ignore_classes: Sequence[int] = (),
    eps: float = 1.0,
    max_weight: float | None = MAX_CLASS_WEIGHT,
) -> list[float]:
    """Normalised inverse-frequency class weights from per-class pixel counts.

    Rare classes get a larger weight, the dominant background a smaller one, so
    the cross-entropy gradient stops collapsing toward the majority class. The
    scheme:

      weight_c = total_pixels / (num_classes * (count_c + eps))

    then normalise so the mean weight over the KEPT classes is 1.0 (leaving the
    overall loss scale — and hence the effective learning rate — comparable to
    plain CE), then clamp each kept weight to ``max_weight``. ``ignore_classes``
    (e.g. the non-food sentinels) are pinned to weight 1.0 and excluded from the
    normalisation mean, so they neither dominate nor rescale the food-class
    weights.

    Classes with a ZERO pixel count are pinned the same way automatically: a CE
    class weight only applies where the class appears as a target, so an
    absent-from-train class's weight is never used — but its near-infinite raw
    inverse frequency would otherwise inflate the normalisation mean and squash
    every real weight towards zero. ``eps`` (Laplace add-one by default) keeps
    the arithmetic finite regardless.

    Pure arithmetic on plain floats — ``train.py`` wraps the result in a
    ``torch.tensor`` on the training device.
    """
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
        1.0 if c in pinned else total / (num_classes * (counts[c] + eps))
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

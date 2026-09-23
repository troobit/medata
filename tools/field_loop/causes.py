#!/usr/bin/env python3
"""The Req 4.4 cause taxonomy, and the evidence each classification stands on.

Deterministic classification only. This module never reads the note's free
text: household measures ("two slices", "half a bowl") are the note's content
and interpreting them is the agent phase's job, with the interpreting model's
ident recorded. What is decidable from the corpus alone — which classes the
replay priced, how the estimate moved across a cluster, whether the stated
carbohydrate figure is even outside replay noise — is decided here, and
everything else is handed on as `undetermined` rather than guessed.

Every classification carries the evidence that produced it, because
`field_close`'s first guard refuses a fix whose cited evidence does not fit its
claimed cause: density, scale, mask and class errors all explain the same carb
delta, so an unevidenced attribution is a coin toss with a rationale attached.
"""

from __future__ import annotations

# The taxonomy. `within_replay_noise` and `undetermined` are not failures of
# the classifier — they are the two honest answers, and both block auto-apply.
WRONG_CLASS = "wrong_class_selection"
ABSENT_FROM_PALETTE = "food_absent_from_palette"
WRONG_MASK = "wrong_mask_coverage"
WRONG_SCALE = "wrong_scale_volume"
WRONG_DENSITY = "wrong_density_conversion"
REFUSAL_SHOULD_HAVE_SUCCEEDED = "refusal_should_have_succeeded"
WITHIN_REPLAY_NOISE = "within_replay_noise"
UNDETERMINED = "undetermined"

TAXONOMY = (WRONG_CLASS, ABSENT_FROM_PALETTE, WRONG_MASK, WRONG_SCALE,
            WRONG_DENSITY, REFUSAL_SHOULD_HAVE_SUCCEEDED, WITHIN_REPLAY_NOISE,
            UNDETERMINED)

# Which evidence fields a cause must carry to be actable. field_close guard 1
# checks exactly this, so the two cannot drift.
REQUIRED_EVIDENCE = {
    WRONG_DENSITY: ("class_agreement", "volume_agreement", "mass_disagreement"),
    WRONG_SCALE: ("class_agreement", "volume_spread"),
    WRONG_MASK: ("mask_inconsistency",),
    WRONG_CLASS: ("reference_class_disagreement",),
    ABSENT_FROM_PALETTE: ("reference_class_unmapped",),
    REFUSAL_SHOULD_HAVE_SUCCEEDED: ("refusal_failure",),
}


def classify(diagnosis: dict, cluster_rows: list, floor_g, reference=None) -> tuple:
    """(cause, evidence) for one annotated capture.

    `cluster_rows` are the other attempts on the same scene — the only place
    mask consistency and volume spread can be measured. `floor_g` is the Req
    4.3 attribution floor, or None when too few skew-free pairs exist to have
    measured one, in which case nothing is attributable at all.
    """
    evidence = {"stem": diagnosis["stem"], "cluster_size": len(cluster_rows)}

    status = diagnosis.get("replay_status")
    stated_carbs = diagnosis.get("stated_carbs_g")
    predicted = diagnosis.get("predicted_total_carbs_g")

    if status in ("not_replayable", "replay_zero_meals", "missing_bundle"):
        # A pre-segmentation refusal carries no mask and no priced class: the
        # evidence is structurally absent (Req 4.4), which is a recorded fact
        # about this capture rather than a gap in the analysis.
        evidence["structurally_absent"] = ["mask", "per_class_volumes"]
        evidence["refusal_failure"] = diagnosis.get("replay_failure_reason") or status
        if diagnosis.get("stated_food_present"):
            return REFUSAL_SHOULD_HAVE_SUCCEEDED, evidence
        return UNDETERMINED, evidence

    if floor_g is None:
        evidence["floor"] = "unmeasured"
        return UNDETERMINED, evidence
    evidence["floor_g"] = floor_g

    if stated_carbs is None or predicted is None:
        evidence["gap_g"] = None
        return UNDETERMINED, evidence

    gap = predicted - stated_carbs
    evidence["gap_g"] = round(gap, 3)
    evidence["stated_carbs_g"] = stated_carbs
    evidence["predicted_total_carbs_g"] = predicted
    if abs(gap) <= floor_g:
        # Req 4.3: smaller than the device-vs-replay delta, so it is not
        # evidence of anything about the data.
        return WITHIN_REPLAY_NOISE, evidence

    if reference:
        picked = set(diagnosis.get("predicted_classes") or [])
        seen = set(reference.get("classes") or [])
        unmapped = list(reference.get("unmapped") or [])
        if unmapped:
            evidence["reference_class_unmapped"] = sorted(unmapped)
            evidence["reference_ident"] = reference.get("ident")
            return ABSENT_FROM_PALETTE, evidence
        if seen and picked and not (seen & picked):
            evidence["reference_class_disagreement"] = {
                "pipeline": sorted(picked), "reference": sorted(seen)}
            evidence["reference_ident"] = reference.get("ident")
            return WRONG_CLASS, evidence

    consistency = mask_consistency(cluster_rows)
    evidence.update(consistency)
    if consistency["dominant_agreement"] is not None \
            and consistency["dominant_agreement"] < 1.0:
        evidence["mask_inconsistency"] = consistency["dominant_agreement"]
        return WRONG_MASK, evidence

    spread = volume_spread(cluster_rows)
    if spread is not None:
        evidence["volume_spread"] = spread
    if spread is not None and spread > 0.25:
        evidence["class_agreement"] = True
        return WRONG_SCALE, evidence

    # Classes agree across the cluster and the volumes are steady, so the
    # conversion from a stable volume to a mass is what is off.
    if spread is not None and consistency["dominant_agreement"] == 1.0:
        evidence["class_agreement"] = True
        evidence["volume_agreement"] = True
        evidence["mass_disagreement"] = round(gap, 3)
        return WRONG_DENSITY, evidence

    return UNDETERMINED, evidence


def mask_consistency(cluster_rows: list) -> dict:
    """The Req 6.1 measure, pinned in design as three numbers.

    Within-cluster dominant-class agreement, mean pairwise argmax IoU, and the
    coefficient of variation of total carbohydrate across the cluster. All
    three are None on a cluster of one — a single attempt is not consistent or
    inconsistent, and reporting 1.0 there would be a fabricated reassurance.
    """
    replayed = [r for r in cluster_rows if r.get("replay_status") == "replayed"]
    if len(replayed) < 2:
        return {"dominant_agreement": None, "mean_pairwise_iou": None,
                "carbs_cov": None}

    dominants = [r.get("dominant_class") for r in replayed]
    top = max(set(dominants), key=dominants.count)
    agreement = dominants.count(top) / len(dominants)

    sets = [set(r.get("predicted_classes") or []) for r in replayed]
    ious = []
    for i in range(len(sets)):
        for j in range(i + 1, len(sets)):
            union = sets[i] | sets[j]
            ious.append(len(sets[i] & sets[j]) / len(union) if union else 0.0)
    mean_iou = sum(ious) / len(ious) if ious else None

    carbs = [r.get("predicted_total_carbs_g") for r in replayed
             if r.get("predicted_total_carbs_g") is not None]
    cov = None
    if len(carbs) >= 2:
        mean = sum(carbs) / len(carbs)
        if mean:
            variance = sum((c - mean) ** 2 for c in carbs) / len(carbs)
            cov = (variance ** 0.5) / abs(mean)

    return {"dominant_agreement": round(agreement, 4),
            "mean_pairwise_iou": round(mean_iou, 4) if mean_iou is not None else None,
            "carbs_cov": round(cov, 4) if cov is not None else None}


def volume_spread(cluster_rows: list):
    """Coefficient of variation of total recovered volume across a cluster.

    A steady scene whose recovered volume swings is a scale problem; a steady
    volume whose mass is wrong is a density problem. This is the number that
    separates the two, which is why guard 1 demands it for both causes.
    """
    totals = []
    for row in cluster_rows:
        volumes = row.get("per_class_volumes_cm3") or {}
        if volumes:
            totals.append(sum(volumes.values()))
    if len(totals) < 2:
        return None
    mean = sum(totals) / len(totals)
    if not mean:
        return None
    variance = sum((t - mean) ** 2 for t in totals) / len(totals)
    return round((variance ** 0.5) / abs(mean), 4)


def attribution_floor(deltas: list, percentile: int, min_pairs: int):
    """Req 4.3's floor, from SKEW-FREE device-vs-replay pairs only.

    Callers filter the skewed pairs out before calling: once the loop lands
    fixes, HEAD-vs-device drift would otherwise be measured as replay noise and
    absorb the loop's own effect. Below `min_pairs` the answer is None — not
    zero, which would silently make everything attributable.
    """
    values = sorted(abs(d) for d in deltas if d is not None)
    if len(values) < min_pairs:
        return None
    rank = (percentile / 100.0) * (len(values) - 1)
    low = int(rank)
    high = min(low + 1, len(values) - 1)
    weight = rank - low
    return round(values[low] * (1 - weight) + values[high] * weight, 4)

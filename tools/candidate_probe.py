#!/usr/bin/env python3
"""Decision 11 probe: does the segmenter's discarded probability mass carry
plate-specific signal, or is it a popularity list?

`specs/estimation/alternative-class-candidates/` defers one design choice to
evidence: the statistic that ranks candidate classes for a detected food. Two
degenerate modes would make the whole spec return a neutral Req 8 verdict for
reasons unrelated to the idea:

  * boundary bleed  — a band around every mask edge contributes more mass to
    whatever is physically adjacent than a genuine confusion contributes to the
    right answer, so rank 1 is "what touches this food";
  * prior domination — after the winner takes its share the residual simplex is
    shaped by the model's marginal class prior, so every plate gets the same
    top-5.

Either reproduces the `perClassMeanProb` failure `ui/meal-review` Decision 13
diagnosed: a plausible number answering the wrong question. This script measures
both, for two candidate statistics, over real tensors.

Reported per statistic:
  (a) top-5 set constancy   — how concentrated the candidate slots are across
      all (plate, food) pairs. A handful of classes filling most slots is the
      prior-domination signature.
  (b) rank-1 adjacency share — how often rank 1 is a class whose own pixels
      physically touch the detected food's region on that plate. A high share is
      the boundary-bleed signature.

Statistics compared:
  mean      — mean probability of the channel over the food's sampled pixels
              (the design's provisional choice)
  runnerup  — fraction of the food's sampled pixels where the channel is the top
              NON-winning channel (second-argmax share)

Two admissible inputs. Capture-bundle `.fixture` files carry the persisted
regularised argmax beside the FP16 tensor; Nutrition5k fixtures carry the
GROUND-TRUTH mask in the same field, so computing evidence over their regions
would be a plausible-looking wrong number (design.md, "Admissible fixtures") and
any bundle with `source_dataset` set is refused. `--validation` instead runs the
shipped checkpoint over a remapped split, which Decision 11 also admits: the
field bundles are single-food plates, so neither adjacency nor constancy across
foods is measurable on them. That leg also has ground-truth masks, which is how
the hit-rate figure below is obtained.

Sampling matches what the design fixes for the shipped pass so the probe
measures the thing that would ship: stride 4 in both axes anchored at (0, 0),
FP16 tensor decoded as-is, the bundle's argmax (which for capture bundles IS the
regularised map — PostProcessing.swift:214), and a 64-sample floor per detected
class.

Usage:
    tools/candidate_probe.py tmp/device_captures/*.fixture --json out.json
    tools/segmenter/.venv/bin/python tools/candidate_probe.py --validation --limit 200

The second form needs the segmenter venv (torch). `--erode N` strips N sampled-grid
layers off each region first, which is the boundary-bleed test.
"""

import argparse
import json
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

# PbMealFixture field numbers (MedataCore/Sources/PortableContracts/Schemas/MealFixture.proto).
F_FIXTURE_ID = 1
F_PALETTE_VERSION = 3
F_NADIR_PROBS = 9
F_NADIR_ARGMAX = 11
F_NADIR_INTRINSICS = 13
F_SOURCE_DATASET = 22

STRIDE = 4          # design: fixed stride-4 grid in both axes, anchored at (0, 0)
SAMPLE_FLOOR = 64   # Decision 11: fewer sampled pixels than this earns no entry
TOP_N = 5           # Req 1.5
ERODE = [0]         # --erode: sampled-grid layers stripped off each region first

# ClassPalette.standard (MedataCore/Sources/Segmentation/ClassPalette.swift).
# Indices 0-24 solids, 25-32 liquids, 33 background, 34 unknown_food,
# 35 unsupported_liquid. "v2" is the expunged pre-release label (pipeline
# Decision 50) naming the SAME 25-solid palette; bundles recorded by pre-expunge
# binaries carry it immutably.
SOLIDS = [
    "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
    "potato_boiled", "potato_mashed", "chips_fries", "chicken", "beef",
    "pork", "fish_white", "egg", "cheese", "salad_leaves",
    "broccoli", "carrot", "peas", "beans_baked", "lentils",
    "apple", "banana", "tomato", "mixed_vegetables", "cereal",
]
LIQUIDS = ["water", "coffee", "tea", "milk", "fruit_juice", "soup", "beer", "wine"]
N_SOLID, N_LIQUID = len(SOLIDS), len(LIQUIDS)
BACKGROUND, UNKNOWN_FOOD, UNSUPPORTED_LIQUID = 33, 34, 35
N_CHANNEL = N_SOLID + N_LIQUID + 3
CLASS_NAMES = SOLIDS + LIQUIDS + ["background", "unknown_food", "unsupported_liquid"]


def is_solid(idx):
    return 0 <= idx < N_SOLID


def is_liquid(idx):
    return N_SOLID <= idx < N_SOLID + N_LIQUID


def is_food(idx):
    return is_solid(idx) or is_liquid(idx)


# ---------------------------------------------------------------- proto reading

def read_varint(buf, i):
    value = shift = 0
    while True:
        byte = buf[i]
        i += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        if not byte & 0x80:
            return value, i


def fields(buf):
    """Yield (field_number, payload) for a proto3 message, payload by wire type."""
    i = 0
    while i < len(buf):
        key, i = read_varint(buf, i)
        number, wire = key >> 3, key & 7
        if wire == 0:
            value, i = read_varint(buf, i)
            yield number, value
        elif wire == 1:
            yield number, buf[i:i + 8]
            i += 8
        elif wire == 2:
            length, i = read_varint(buf, i)
            yield number, buf[i:i + length]
            i += length
        elif wire == 5:
            yield number, struct.unpack_from("<f", buf, i)[0]
            i += 4
        else:
            raise ValueError(f"unsupported wire type {wire} for field {number}")


def first(buf, number):
    for n, payload in fields(buf):
        if n == number:
            return payload
    return None


def parse_intrinsics(buf):
    out = {"width": 0, "height": 0}
    for n, payload in fields(buf):
        if n == 6:
            out["width"] = payload
        elif n == 7:
            out["height"] = payload
    return out


# ------------------------------------------------------------------- the probe

def adjacent_classes(argmax_2d, class_idx):
    """Classes whose pixels touch `class_idx`'s region, 4-connected.

    Computed on the FULL-resolution argmax, not the sampled grid: adjacency is a
    property of the plate, and the stride would fabricate or hide contacts.
    """
    region = argmax_2d == class_idx
    if not region.any():
        return set()
    touching = set()
    # Shift the region one pixel each way and read what the neighbour sits on.
    for shifted, target in (
        (region[:-1, :], argmax_2d[1:, :]),
        (region[1:, :], argmax_2d[:-1, :]),
        (region[:, :-1], argmax_2d[:, 1:]),
        (region[:, 1:], argmax_2d[:, :-1]),
    ):
        touching.update(np.unique(target[shifted]).tolist())
    touching.discard(class_idx)
    return {c for c in touching if is_food(c)}


def erode(mask, steps):
    """Shrink a boolean region by `steps` 4-connected layers, off-grid = outside.

    Applied on the SAMPLED grid, so one step is `STRIDE` pixels of the original
    frame. This is the direct test of the boundary-bleed hypothesis: if rank 1 is
    an artefact of a band around the mask edge, dropping that band should collapse
    the adjacency share towards chance. If it does not, the adjacency is coming
    from the interior and is not bleed.
    """
    for _ in range(steps):
        keep = np.zeros_like(mask)
        keep[1:-1, 1:-1] = (mask[1:-1, 1:-1] & mask[:-2, 1:-1] & mask[2:, 1:-1]
                            & mask[1:-1, :-2] & mask[1:-1, 2:])
        mask = keep
        if not mask.any():
            break
    return mask


def eligible_channels(own_idx):
    """Channels a candidate set for `own_idx` may contain (Req 1.4, 1.6)."""
    same_phase = is_solid if is_solid(own_idx) else is_liquid
    return np.array([c for c in range(N_CHANNEL)
                     if c != own_idx and same_phase(c)], dtype=np.intp)


def candidates_for(probs_flat, own_idx):
    """Both statistics for one detected class.

    `probs_flat` is [n_samples, C] FP32 for the pixels the regularised map gives
    this class. Ranking is on the raw statistic (no quantisation), ties broken by
    channel declaration order, which `np.argsort(kind="stable")` preserves.

    Both statistics are computed over the ELIGIBLE channels only — the food's own
    class, background, the two sentinels and the opposite phase are removed first
    rather than ranked and then filtered. For the mean this is cosmetic. For the
    runner-up share it is the difference between a statistic and nothing at all:
    taken literally ("the top non-winning channel"), the runner-up is background
    at almost every food pixel, so every eligible class scores zero and the
    ranking is empty. `background_runnerup_share` reports how dominant that is,
    because it is evidence about the tensor rather than a detail of this script.
    """
    n = probs_flat.shape[0]
    elig = eligible_channels(own_idx)

    # How often the literal top non-winner is background or a sentinel — the
    # reason the runner-up statistic must be taken over eligible channels.
    order = np.argsort(-probs_flat, axis=1, kind="stable")
    literal_runner = order[:, 1]
    non_food = np.isin(literal_runner, [BACKGROUND, UNKNOWN_FOOD, UNSUPPORTED_LIQUID])
    background_share = float(non_food.mean())

    sub = probs_flat[:, elig]                       # [n, len(elig)]
    means_sub = sub.mean(axis=0)
    # Strongest eligible alternative per pixel, as a share of the food's pixels.
    best = np.argmax(sub, axis=1)                   # ties -> lowest index = declaration order
    runnerup_sub = np.bincount(best, minlength=elig.size).astype(np.float64) / n

    out = {}
    for name, values in (("mean", means_sub), ("runnerup", runnerup_sub)):
        ranked = []
        for pos in np.argsort(-values, kind="stable"):
            if values[pos] <= 0.0:
                continue
            ranked.append((int(elig[pos]), float(values[pos])))
            if len(ranked) == TOP_N:
                break
        out[name] = ranked
    # Full eligible-channel mean vector, kept so the prior-domination test can
    # correlate this food's ordering against the corpus-wide one. The top-5 slot
    # histogram cannot carry that question on a corpus this small.
    vector = {CLASS_NAMES[int(c)]: float(v) for c, v in zip(elig, means_sub)}
    return out, background_share, vector


def probe_bundle(path):
    raw = Path(path).read_bytes()
    fixture_id = first(raw, F_FIXTURE_ID).decode()

    source = first(raw, F_SOURCE_DATASET)
    if source:
        raise SystemExit(
            f"{fixture_id}: source_dataset={source.decode()!r} — dataset fixtures carry a "
            "ground-truth mask in nadir_argmax, not a persisted prediction, and are "
            "inadmissible for this probe (design.md, 'Admissible fixtures')"
        )

    palette_version = first(raw, F_PALETTE_VERSION).decode()
    probs_buf = first(raw, F_NADIR_PROBS)
    argmax_buf = first(raw, F_NADIR_ARGMAX)
    if not probs_buf or not argmax_buf:
        raise SystemExit(f"{fixture_id}: no probs/argmax — a refusal bundle, nothing to probe")

    intr = parse_intrinsics(first(raw, F_NADIR_INTRINSICS))
    w, h = intr["width"], intr["height"]
    if len(argmax_buf) != w * h:
        raise SystemExit(f"{fixture_id}: argmax {len(argmax_buf)} bytes, expected {w * h}")
    # Trust the tensor's shape over the palette stamp. Some bundles carry a stale
    # label ("v1", "v2") from a binary that stamped a name the palette had already
    # outgrown — the same provenance-stamp defect the palette expunge (pipeline
    # Decision 50) cleaned up. A genuine 24-solid palette would give 35 channels;
    # 36 IS the current palette whatever the stamp says. Refusing on the label
    # would discard real captures over a string.
    channels = len(probs_buf) / (w * h * 2)
    if channels != N_CHANNEL:
        raise SystemExit(
            f"{fixture_id}: probs imply {channels:g} channels, expected {N_CHANNEL} "
            f"for the current palette — not readable with this class list"
        )

    argmax = np.frombuffer(argmax_buf, dtype=np.uint8).reshape(h, w)
    probs = np.frombuffer(probs_buf, dtype="<f2").reshape(h, w, N_CHANNEL)

    # The sampling the shipped pass would use.
    sampled_argmax = argmax[::STRIDE, ::STRIDE]
    sampled_probs = probs[::STRIDE, ::STRIDE, :]

    detected = [c for c in np.unique(sampled_argmax).tolist() if is_food(c)]
    rows = []
    for class_idx in detected:
        pick = sampled_argmax == class_idx
        if ERODE[0]:
            pick = erode(pick, ERODE[0])
        n = int(pick.sum())
        if n < SAMPLE_FLOOR:
            rows.append({
                "class": CLASS_NAMES[class_idx], "samples": n, "floored": True,
                "candidates": {}, "adjacent": [],
            })
            continue
        # FP32 only for the pixels actually sampled — the whole tensor as FP32
        # would be ~400 MB.
        flat = sampled_probs[pick].astype(np.float32)
        cands, background_share, vector = candidates_for(flat, class_idx)
        adj = adjacent_classes(argmax, class_idx)
        rows.append({
            "class": CLASS_NAMES[class_idx],
            "samples": n,
            "floored": False,
            "background_runnerup_share": background_share,
            "mean_vector": vector,
            "adjacent": sorted(CLASS_NAMES[a] for a in adj),
            "candidates": {
                stat: [{"class": CLASS_NAMES[i], "value": v,
                        "adjacent": i in adj} for i, v in ranked]
                for stat, ranked in cands.items()
            },
        })

    return {
        "fixture_id": fixture_id,
        "palette_version": palette_version,
        "grid": [h, w],
        "sampled_pixels": int(sampled_argmax.size),
        "foods": rows,
    }


# ------------------------------------------------------------------- reporting

def summarise(results, statistic):
    """Constancy and adjacency for one statistic across every scored food."""
    slot_counts = Counter()      # every class appearing in any top-5 slot
    rank1_counts = Counter()
    sets = []                    # each food's top-5 as a frozenset, for overlap
    rank1_adjacent = 0
    rank1_total = 0
    per_plate_rank1 = defaultdict(list)

    for bundle in results:
        for food in bundle["foods"]:
            ranked = food["candidates"].get(statistic)
            if not ranked:
                continue
            sets.append(frozenset(c["class"] for c in ranked))
            slot_counts.update(c["class"] for c in ranked)
            top = ranked[0]
            rank1_counts[top["class"]] += 1
            rank1_total += 1
            if top["adjacent"]:
                rank1_adjacent += 1
            per_plate_rank1[bundle["fixture_id"]].append(top["class"])

    # Chance-level adjacency: if rank 1 were drawn uniformly from the eligible
    # classes, how often would it happen to touch the food? Without this the
    # observed share is unreadable — on a crowded plate a high share may be
    # arithmetic rather than bleed.
    chance = []
    for bundle in results:
        for food in bundle["foods"]:
            if food["floored"] or not food["candidates"].get(statistic):
                continue
            own = CLASS_NAMES.index(food["class"])
            n_elig = eligible_channels(own).size
            same_phase = is_solid if is_solid(own) else is_liquid
            n_adj = sum(1 for a in food["adjacent"]
                        if same_phase(CLASS_NAMES.index(a)))
            if n_elig:
                chance.append(n_adj / n_elig)
    chance_adjacency = float(np.mean(chance)) if chance else 0.0

    total_slots = sum(slot_counts.values())
    top5_share = (sum(c for _, c in slot_counts.most_common(TOP_N)) / total_slots
                  if total_slots else 0.0)

    # Mean pairwise Jaccard over the top-5 sets: 1.0 means every food on every
    # plate produced the same five candidates.
    jac = []
    for i in range(len(sets)):
        for j in range(i + 1, len(sets)):
            a, b = sets[i], sets[j]
            union = len(a | b)
            jac.append(len(a & b) / union if union else 0.0)
    mean_jaccard = sum(jac) / len(jac) if jac else 0.0

    return {
        "scored_foods": len(sets),
        "distinct_classes_in_any_slot": len(slot_counts),
        "top5_slot_share": top5_share,
        "mean_pairwise_jaccard": mean_jaccard,
        "distinct_rank1_classes": len(rank1_counts),
        "rank1_adjacency_share": (rank1_adjacent / rank1_total) if rank1_total else 0.0,
        "chance_adjacency_share": chance_adjacency,
        "rank1_total": rank1_total,
        "slot_histogram": slot_counts.most_common(),
        "rank1_histogram": rank1_counts.most_common(),
    }


def _ranks(values):
    """Ascending competition-free ranks, ties averaged — enough for Spearman."""
    arr = np.asarray(values, dtype=np.float64)
    order = np.argsort(arr, kind="stable")
    ranks = np.empty(arr.size, dtype=np.float64)
    ranks[order] = np.arange(arr.size, dtype=np.float64)
    # Average ties so a flat region cannot manufacture correlation.
    _, inverse, counts = np.unique(arr, return_inverse=True, return_counts=True)
    sums = np.zeros(counts.size)
    np.add.at(sums, inverse, ranks)
    return (sums / counts)[inverse]


def _spearman(a, b):
    ra, rb = _ranks(a), _ranks(b)
    ra -= ra.mean()
    rb -= rb.mean()
    denom = np.sqrt((ra * ra).sum() * (rb * rb).sum())
    return float((ra * rb).sum() / denom) if denom else 0.0


def prior_domination(results):
    """Is each food's candidate ordering just the corpus-wide marginal ordering?

    For every scored food, correlate its eligible-channel mean vector against the
    pooled mean vector built from every OTHER food (leave-one-out, so a food
    cannot correlate with itself). A high median correlation means the ranking is
    the model's marginal class prior wearing a per-food label — the degenerate
    mode Decision 11 exists to catch. Only channels the two vectors share are
    compared, so a solid never correlates against a liquid's vector.
    """
    foods = [(b["fixture_id"], f) for b in results for f in b["foods"]
             if not f["floored"] and f.get("mean_vector")]
    if len(foods) < 2:
        return {"pairs": len(foods), "median_rho": None, "per_food": []}

    per_food = []
    for i, (fid, food) in enumerate(foods):
        others = [o for j, (_, o) in enumerate(foods) if j != i]
        pooled = defaultdict(list)
        for o in others:
            for name, value in o["mean_vector"].items():
                pooled[name].append(value)
        shared = [n for n in food["mean_vector"] if n in pooled]
        if len(shared) < 3:
            continue
        mine = [food["mean_vector"][n] for n in shared]
        theirs = [float(np.mean(pooled[n])) for n in shared]
        # Whether the TOP of the list agrees with the prior's top matters far
        # more than the whole-vector correlation: a shortlist ships five slots,
        # and Spearman over 24 channels is dominated by the near-zero tail, where
        # agreement is cheap and irrelevant.
        my_top = max(shared, key=lambda n: food["mean_vector"][n])
        prior_top = max(shared, key=lambda n: float(np.mean(pooled[n])))
        my_top5 = sorted(shared, key=lambda n: -food["mean_vector"][n])[:TOP_N]
        prior_top5 = sorted(shared, key=lambda n: -float(np.mean(pooled[n])))[:TOP_N]
        per_food.append({
            "fixture_id": fid, "class": food["class"],
            "channels": len(shared), "rho": _spearman(mine, theirs),
            "top1_matches_prior": my_top == prior_top,
            "top5_overlap_with_prior": len(set(my_top5) & set(prior_top5)) / TOP_N,
        })

    rhos = [p["rho"] for p in per_food]
    return {
        "pairs": len(per_food),
        "median_rho": float(np.median(rhos)) if rhos else None,
        "top1_matches_prior_share": (
            float(np.mean([p["top1_matches_prior"] for p in per_food])) if per_food else None),
        "mean_top5_overlap_with_prior": (
            float(np.mean([p["top5_overlap_with_prior"] for p in per_food])) if per_food else None),
        "per_food": per_food,
    }


def hit_rate(results, statistic):
    """Req 8.1's quantity where ground truth exists: on regions the segmenter got
    wrong, is the true class in the candidate set? Empty dict when the input
    carries no truth (capture bundles do not)."""
    scored = [f for b in results for f in b["foods"]
              if not f["floored"] and f.get("truth_class")]
    wrong = [f for f in scored if not f["correct"]]
    if not wrong:
        return {}
    in_set = sum(1 for f in wrong
                 if any(c["class"] == f["truth_class"]
                        for c in f["candidates"].get(statistic, [])))
    at_1 = sum(1 for f in wrong
               if f["candidates"].get(statistic)
               and f["candidates"][statistic][0]["class"] == f["truth_class"])
    return {"scored": len(scored), "wrong": len(wrong),
            "true_in_topn": in_set / len(wrong), "true_at_rank1": at_1 / len(wrong)}


def corpus_shape(results):
    scored = [f for b in results for f in b["foods"] if not f["floored"]]
    return {
        "plates": len(results),
        "scored_foods": len(scored),
        "distinct_foods": len({f["class"] for f in scored}),
        "multi_food_plates": sum(
            1 for b in results
            if len([f for f in b["foods"] if not f["floored"]]) > 1),
    }


def print_report(results, summaries):
    shape = corpus_shape(results)
    print(f"stride={STRIDE} floor={SAMPLE_FLOOR} top={TOP_N} erode={ERODE[0]}  "
          + "  ".join(f"{k}={v}" for k, v in shape.items()))
    prior = summaries["mean"]["prior_domination"]
    for stat, s in summaries.items():
        hr = hit_rate(results, stat)
        cols = {
            "slots_top5": f"{s['top5_slot_share']:.3f}",
            "jaccard": f"{s['mean_pairwise_jaccard']:.3f}",
            "rank1_classes": s["distinct_rank1_classes"],
            "adjacency": f"{s['rank1_adjacency_share']:.3f}",
            "chance": f"{s['chance_adjacency_share']:.3f}",
        }
        if hr:
            cols["true_in_top5"] = f"{hr['true_in_topn']:.3f}"
            cols["true_at_rank1"] = f"{hr['true_at_rank1']:.3f}"
            cols["wrong_regions"] = hr["wrong"]
        print(f"{stat:<9} " + "  ".join(f"{k}={v}" for k, v in cols.items()))
    if prior["median_rho"] is not None:
        print(f"prior     rho={prior['median_rho']:+.3f}  "
              f"top1_is_prior={prior['top1_matches_prior_share']:.3f}  "
              f"top5_overlap={prior['mean_top5_overlap_with_prior']:.3f}")


def probe_validation(checkpoint, data_dir, split, limit, target_size, device_arg):
    """Run the shipped checkpoint over a remapped split and probe its predictions.

    Decision 11 admits "segmenter validation outputs" beside capture bundles, and
    they answer what the device corpus cannot: the field captures are single-food
    plates, so neither constancy across foods nor rank-1 adjacency is measurable
    on them. Validation images are real multi-food plates and the argmax here is a
    PREDICTION, so unlike an n5k fixture's ground-truth mask it is admissible.

    Two deviations from the device path, both deliberate and neither affecting
    what is being measured:
      * no speckle regularisation — `regulariseLabelMap` is Swift, and
        reimplementing it here would risk divergence from the thing that ships.
        The 64-sample floor already denies evidence to small regions, which is
        most of what the filter would remove.
      * probabilities come from a softmax over the model's logits rather than
        from an FP16 round trip. The probe compares statistics, not bit patterns;
        the FP16 contract matters for replay parity (Req 6.1), which is task 15's
        job, not this one.
    """
    import importlib

    tools_dir = str(Path(__file__).resolve().parent / "segmenter")
    if tools_dir not in sys.path:
        sys.path.insert(0, tools_dir)
    import torch
    train = importlib.import_module("train")
    export = importlib.import_module("export")
    archs = importlib.import_module("archs")

    arch = archs.checkpoint_arch_stamp(checkpoint) or archs.DEFAULT_ARCH
    spec = archs.get(arch)
    model = export.load_checkpoint(N_CHANNEL, checkpoint, arch=arch)
    device = train._resolve_device(device_arg)
    model.to(device).eval()
    dataset = train.FoodSegDataset(Path(data_dir) / split, target_size, limit=limit)

    results = []
    with torch.no_grad():
        for i in range(len(dataset)):
            image, truth = dataset[i]
            truth_np = truth.numpy() if hasattr(truth, "numpy") else np.asarray(truth)
            logits = spec.forward_logits(model, image.unsqueeze(0).to(device))
            probs_t = torch.softmax(logits, dim=1)[0]          # [C, H, W]
            probs = probs_t.permute(1, 2, 0).cpu().numpy().astype(np.float32)
            argmax = probs.argmax(axis=2).astype(np.uint8)

            sampled_argmax = argmax[::STRIDE, ::STRIDE]
            sampled_probs = probs[::STRIDE, ::STRIDE, :]
            rows = []
            for class_idx in (c for c in np.unique(sampled_argmax).tolist() if is_food(c)):
                pick = sampled_argmax == class_idx
                if ERODE[0]:
                    pick = erode(pick, ERODE[0])
                n = int(pick.sum())
                if n < SAMPLE_FLOOR:
                    rows.append({"class": CLASS_NAMES[class_idx], "samples": n,
                                 "floored": True, "candidates": {}, "adjacent": []})
                    continue
                cands, background_share, vector = candidates_for(
                    sampled_probs[pick], class_idx)
                adj = adjacent_classes(argmax, class_idx)
                # The measurement the proxies cannot make: the split carries a
                # ground-truth mask, so for a WRONG region we can ask whether the
                # right answer is in the candidate set. That is Req 8.1's shortlist
                # hit rate, measurable here without waiting for a corrections
                # corpus — for the segmenter's errors rather than the user's.
                sampled_truth = truth_np[::STRIDE, ::STRIDE]
                region_truth = sampled_truth[pick]
                region_truth = region_truth[np.isin(region_truth,
                                                    np.arange(N_SOLID + N_LIQUID))]
                truth_class = (int(np.bincount(region_truth).argmax())
                               if region_truth.size else None)
                rows.append({
                    "class": CLASS_NAMES[class_idx],
                    "samples": n,
                    "floored": False,
                    "background_runnerup_share": background_share,
                    "mean_vector": vector,
                    "adjacent": sorted(CLASS_NAMES[a] for a in adj),
                    "truth_class": CLASS_NAMES[truth_class] if truth_class is not None else None,
                    "correct": truth_class == class_idx,
                    "candidates": {
                        stat: [{"class": CLASS_NAMES[j], "value": v,
                                "adjacent": j in adj} for j, v in ranked]
                        for stat, ranked in cands.items()
                    },
                })
            results.append({
                "fixture_id": f"{split}[{i}]",
                "palette_version": "(model output)",
                "grid": list(argmax.shape),
                "sampled_pixels": int(sampled_argmax.size),
                "foods": rows,
            })
    return results


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("bundles", nargs="*", type=Path)
    ap.add_argument("--json", type=Path, help="write the full per-food detail here")
    ap.add_argument("--validation", action="store_true",
                    help="probe the shipped checkpoint's predictions over a split "
                         "instead of capture bundles (needs the segmenter venv)")
    ap.add_argument("--checkpoint", default="tools/segmenter/build/checkpoint_merged_v2.pt")
    ap.add_argument("--data", default="data/merged_foodseg_foodrec2022")
    ap.add_argument("--split", default="val")
    ap.add_argument("--limit", type=int, default=100)
    ap.add_argument("--target-size", type=int, default=513)
    ap.add_argument("--device", default="auto")
    ap.add_argument("--erode", type=int, default=0,
                    help="strip N sampled-grid layers off each food region before "
                         "accumulating (N*%d px of the frame) — the boundary-bleed test"
                         % STRIDE)
    args = ap.parse_args()

    ERODE[0] = args.erode
    if not args.bundles and not args.validation:
        ap.error("give at least one bundle, or --validation")

    results = []
    if args.validation:
        results += probe_validation(args.checkpoint, args.data, args.split,
                                    args.limit, args.target_size, args.device)
    for path in args.bundles:
        results.append(probe_bundle(path))

    summaries = {stat: summarise(results, stat) for stat in ("mean", "runnerup")}
    summaries["mean"]["prior_domination"] = prior_domination(results)
    print_report(results, summaries)

    if args.json:
        args.json.write_text(json.dumps(
            {"bundles": results, "summary": summaries}, indent=2))


if __name__ == "__main__":
    main()

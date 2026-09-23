#!/usr/bin/env python3
"""Req 8 of `specs/estimation/alternative-class-candidates/`: how often was the
food the user chose already in the shortlist they were offered, and does the
combined ordering beat the recency prior it was built on top of?

The corpus already carries everything the four criteria need — this reads it,
it adds no fields:

  8.1 hit rate       `shortlist_rank > 0` on relabel records (rank 0 means the
                     full list, or no relabel at all)
  8.2 partition      `shortlist_source`: "recency" vs "recency_plus_candidates"
  8.3 baseline       the same metric over both arms
  8.4 first-vs-repeat a corrected class X for predicted class P is a REPEAT iff
                     an earlier relabel record corrects P to X — the same
                     relation the shipped recency query ranks from

Three cuts are part of the deliverable rather than optional extras, because
each one is a way the headline comparison lies:

  * RECENCY DEPTH (Decision 12). The arms are separated in time and recency
    strengthens monotonically as the corpus grows, so a naive comparison
    flatters the combined arm. The offered order cannot be replayed —
    `updated_at` is rewritten by later mutations — but the *count* of distinct
    earlier P → X corrections at each record's timestamp can be reconstructed
    from `created_at`, and stratifying on it separates "the ordering improved"
    from "the history got deeper".
  * AS-TREATED (Decision 12). `shortlist_source` follows the marker, not the
    fills: a combined-arm record whose evidence set was empty for its predicted
    class still reads "recency_plus_candidates". That keeps the 8.2 partition a
    property of the code path, and it attenuates the per-class question. The
    meal record persists the evidence map, so the rows that were treated in
    name only are identifiable offline.
  * BOUNDARY BLEED (Decision 13). Rank-1 candidates physically touch the food
    69.7% of the time against a 9.1% chance baseline, and erosion does not
    remove it. Splitting the combined arm by whether the corrected class was
    ADJACENT to the predicted region distinguishes the two readings of that
    number: adjacency as genuine confusion (a neighbour's label smeared over
    the region — bleed IS the signal) from adjacency as noise crowding real
    confusions out of the five slots. Adjacent hitting while non-adjacent
    misses is the second reading, and fires the mitigation task.

Every figure prints its cell count beside it. On a corpus this size that is not
decoration: a rate over three rows is not a verdict, and `bleed_verdict` stays
`insufficient` until both cells clear `--min-cell`.

Inputs, all optional except the first:

    tools/shortlist_hit_rate.py tmp/device_pulls/*.sqlite --bundles tmp/device_captures

  * SQLite pulls (or the archive export) — `correction_records` for the corpus
    and the `events` meal rows for the as-treated cut. Rows are deduplicated on
    (meal_id, predicted_class), newest `updated_at` winning, so successive pulls
    of the same device can all be passed at once.
  * `.jsonl` — the app's Corrections export. Same rows, no meal records, so the
    as-treated cut reports `unknown` for everything.
  * `--bundles DIR` — capture bundles for the adjacency cut. A bundle is matched
    to a meal by timestamp (the bundle is stamped when estimation starts, the
    record when it finishes) and the match is then VERIFIED against the meal's
    detected classes; an unverifiable row is reported `unknown`, never assumed
    non-adjacent.
"""

import argparse
import json
import sqlite3
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

# The palette, the minimal proto reader and the adjacency relation are the
# probe's, not copies of it: a second class list that drifted from the first
# would make the boundary-bleed cut disagree with the figures it is judged
# against.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from candidate_probe import (
    CLASS_NAMES,
    adjacent_classes,
    first,
    is_food,
    parse_intrinsics,
)

# ShortlistOrdering.swift — the two values `shortlist_source` can take.
RECENCY_ARM = "recency"
COMBINED_ARM = "recency_plus_candidates"
ARMS = (RECENCY_ARM, COMBINED_ARM)

# PbMealFixture field numbers, as in candidate_probe.
F_NADIR_ARGMAX = 11
F_NADIR_INTRINSICS = 13
F_SOURCE_DATASET = 22

DEPTH_BUCKETS = ("0", "1-2", "3-4", "5+")


def depth_bucket(depth):
    if depth == 0:
        return "0"
    if depth <= 2:
        return "1-2"
    if depth <= 4:
        return "3-4"
    return "5+"


# ------------------------------------------------------------------ corpus load

def _int(value):
    """protobuf-JSON encodes int64 as a string; everything else arrives typed."""
    return int(value) if value is not None else 0


def correction_row(record):
    """The fields this analysis reads, from one protobuf-JSON correction record.

    proto3 omits defaults, so an absent `shortlistRank` is 0 (no relabel / full
    list) and an absent `classCorrected` is false — the same reading the app's
    decoder gives them.
    """
    predicted = record.get("predicted") or {}
    corrected = record.get("corrected") or {}
    return {
        "meal_id": record.get("mealId", ""),
        "predicted_class": predicted.get("classId", ""),
        "predicted_index": predicted.get("classIndex"),
        "corrected_class": corrected.get("classId", ""),
        "created_at_ms": _int(record.get("createdAtMs")),
        "updated_at_ms": _int(record.get("updatedAtMs")),
        "class_corrected": bool(record.get("classCorrected", False)),
        "shortlist_rank": int(record.get("shortlistRank", 0)),
        "shortlist_source": record.get("shortlistSource", ""),
        "was_reverted": bool(record.get("wasReverted", False)),
        "segmenter_source": record.get("segmenterSource", ""),
    }


def load_sqlite(path):
    """Correction records and meal records from one device pull or archive."""
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        rows = [correction_row(json.loads(text)) for (text,) in db.execute(
            "SELECT CAST(record_json AS TEXT) FROM correction_records")]
        meals = {}
        for meal_id, metadata in db.execute(
                "SELECT id, CAST(metadata AS TEXT) FROM events WHERE event_type = 'meal'"):
            # The event metadata is an envelope: the protobuf-JSON meal record
            # as a string, beside the SQL-only palette version.
            envelope = json.loads(metadata)
            meals[meal_id] = json.loads(envelope["record"])
        return rows, meals
    finally:
        db.close()


def load_jsonl(path):
    rows = [correction_row(json.loads(line))
            for line in Path(path).read_text().splitlines() if line.strip()]
    return rows, {}


def load(paths):
    """Merge every input, deduplicating on the correction store's primary key.

    (meal_id, predicted_class) is that key; the newest `updated_at` wins, which
    is what the store itself would hold after the same sequence of edits.
    """
    rows, meals = {}, {}
    for path in paths:
        loaded, loaded_meals = (
            load_jsonl(path) if path.suffix == ".jsonl" else load_sqlite(path))
        for row in loaded:
            key = (row["meal_id"], row["predicted_class"])
            if key not in rows or row["updated_at_ms"] > rows[key]["updated_at_ms"]:
                rows[key] = row
        meals.update(loaded_meals)
    return sorted(rows.values(), key=lambda r: (r["created_at_ms"], r["predicted_class"])), meals


# ------------------------------------------------------- reconstructed recency

def annotate_recency(relabels):
    """First-vs-repeat (Req 8.4) and recency depth (Decision 12), per row.

    Both are reconstructed from `created_at`, not `updated_at`: a later edit
    rewrites `updated_at`, so it cannot order the corpus as it stood when a
    given shortlist was offered. Rows sharing a timestamp (the several foods of
    one plate) are not earlier than each other, so neither sees the other.

    Depth is the count of DISTINCT corrected classes already recorded for the
    same predicted class — the size of the pool the shipped recency query drew
    from, which is reconstructible even though its order is not.
    """
    history = defaultdict(list)   # predicted class -> [(created_at_ms, corrected)]
    for row in relabels:
        earlier = {corrected for stamp, corrected in history[row["predicted_class"]]
                   if stamp < row["created_at_ms"]}
        row["recency_depth"] = len(earlier)
        row["repeat"] = row["corrected_class"] in earlier
        history[row["predicted_class"]].append(
            (row["created_at_ms"], row["corrected_class"]))


# ---------------------------------------------------------------- as-treated

def annotate_as_treated(relabels, meals):
    """Did the combined arm's evidence actually carry a set for this food?

    Four outcomes, and the last two are different facts: `marker_false` on a
    combined-arm row is an integrity failure (the source is supposed to follow
    the marker), while `no_meal_record` is just a meal this input does not
    carry.
    """
    for row in relabels:
        meal = meals.get(row["meal_id"])
        if meal is None:
            row["as_treated"] = "no_meal_record"
            continue
        if not meal.get("candidateEvidenceProduced", False):
            row["as_treated"] = "marker_false"
            continue
        evidence = (meal.get("candidateEvidence") or {}).get(row["predicted_class"]) or {}
        names = evidence.get("classNames") or []
        permille = evidence.get("meanPermille") or []
        # Equal lengths are a writer-enforced invariant every reader checks; a
        # mismatch reads as no evidence for that class, never as an error.
        row["as_treated"] = "evidence" if names and len(names) == len(permille) else "no_evidence"


# ----------------------------------------------------------------- adjacency

def load_bundles(directory):
    """Every admissible capture bundle in `directory`, as (timestamp, argmax).

    A bundle with `source_dataset` set is Nutrition5k-derived: its argmax field
    carries the ground-truth mask rather than a persisted prediction, so it is
    refused here for the same reason `candidate_probe.py` refuses it.
    """
    import numpy as np

    bundles = []
    for path in sorted(Path(directory).glob("*.fixture")):
        raw = path.read_bytes()
        if first(raw, F_SOURCE_DATASET):
            continue
        argmax_buf = first(raw, F_NADIR_ARGMAX)
        intrinsics = first(raw, F_NADIR_INTRINSICS)
        if not argmax_buf or not intrinsics:
            continue                      # a refusal bundle carries no mask
        size = parse_intrinsics(intrinsics)
        width, height = size["width"], size["height"]
        if len(argmax_buf) != width * height:
            continue
        # The bundle's stem is the timestamp estimation STARTED, in epoch ms.
        stem = path.stem.split("-")[0]
        if not stem.isdigit():
            continue
        argmax = np.frombuffer(argmax_buf, dtype=np.uint8).reshape(height, width)
        bundles.append({
            "path": path,
            "timestamp_ms": int(stem),
            "argmax": argmax,
            "classes": {CLASS_NAMES[c] for c in np.unique(argmax).tolist() if is_food(c)},
        })
    return bundles


def match_bundles(meals, bundles, window_ms):
    """Meal id -> bundle, by timestamp and then verified against the mask.

    The bundle is stamped when estimation starts and the meal record when it
    finishes, so the bundle is the nearest one strictly BEFORE the record within
    `window_ms`. Timestamp alone would be a guess, so the candidate must also
    explain the meal: every class the estimate carries must be present in the
    bundle's argmax. (Not the converse — speckle the estimate drops below its
    area threshold is still in the mask.) A meal no bundle explains is absent
    from this map and its rows report `unknown`.
    """
    matched = {}
    for meal_id, meal in meals.items():
        created = _int(meal.get("createdAtMs"))
        detected = set((meal.get("volumes") or {}).get("perClassVolumesCm3") or {})
        best = None
        for bundle in bundles:
            delta = created - bundle["timestamp_ms"]
            if not 0 <= delta <= window_ms:
                continue
            if not detected or not detected <= bundle["classes"]:
                continue
            if best is None or delta < best[0]:
                best = (delta, bundle)
        if best:
            matched[meal_id] = best[1]
    return matched


def annotate_adjacency(relabels, matched):
    """Was the corrected class touching the predicted region on that plate?

    Recomputed from the bundle's persisted argmax at full resolution — adjacency
    is a property of the plate, and the sampling stride would fabricate or hide
    contacts. Unresolvable rows are `unknown` rather than assumed non-adjacent:
    the whole point of the cut is that both sides are real measurements.
    """
    for row in relabels:
        bundle = matched.get(row["meal_id"])
        if bundle is None:
            row["adjacency"] = "unknown"
            continue
        try:
            own = CLASS_NAMES.index(row["predicted_class"])
            other = CLASS_NAMES.index(row["corrected_class"])
        except ValueError:
            row["adjacency"] = "unknown"   # a class this palette does not carry
            continue
        if not (bundle["argmax"] == own).any():
            row["adjacency"] = "unknown"   # the join does not hold for this class
            continue
        row["adjacency"] = ("adjacent" if other in adjacent_classes(bundle["argmax"], own)
                            else "non_adjacent")


# ------------------------------------------------------------------- reporting

def cell(rows):
    hits = sum(1 for row in rows if row["shortlist_rank"] > 0)
    return {"n": len(rows), "hits": hits,
            "rate": (hits / len(rows)) if rows else None}


def fmt(stats):
    rate = "na" if stats["rate"] is None else f"{stats['rate']:.3f}"
    return f"n={stats['n']} hits={stats['hits']} rate={rate}"


def day(ms):
    return time.strftime("%Y-%m-%d", time.gmtime(ms / 1000)) if ms else "na"


def report(rows, relabels, meals, matched, args):
    by_arm = defaultdict(list)
    for row in relabels:
        by_arm[row["shortlist_source"] or "unset"].append(row)

    arm_counts = Counter(row["shortlist_source"] or "unset" for row in rows)
    print(f"corpus rows={len(rows)} meals={len({r['meal_id'] for r in rows})} "
          f"meal_records={len(meals)} relabels={len(relabels)} "
          f"reverted={sum(1 for r in rows if r['was_reverted'])} "
          f"bundles_matched={len(matched)} "
          + " ".join(f"arm[{k}]={v}" for k, v in sorted(arm_counts.items())))

    # Req 8.1/8.2/8.3 — the headline, one line per arm, its baseline beside it.
    for arm in ARMS:
        print(f"hit arm={arm} {fmt(cell(by_arm.get(arm, [])))}")
    for arm in sorted(set(by_arm) - set(ARMS)):
        print(f"hit arm={arm} {fmt(cell(by_arm[arm]))}")

    # Req 8.4 — the split that matters most: recency cannot serve a first
    # correction, so an aggregate dominated by repeats hides the case this spec
    # exists for.
    for arm in ARMS:
        for kind, want in (("first", False), ("repeat", True)):
            subset = [r for r in by_arm.get(arm, []) if r["repeat"] == want]
            print(f"split arm={arm} kind={kind} {fmt(cell(subset))}")

    # Decision 12 (a) — the temporal confound, made measurable.
    for arm in ARMS:
        for bucket in DEPTH_BUCKETS:
            subset = [r for r in by_arm.get(arm, [])
                      if depth_bucket(r["recency_depth"]) == bucket]
            print(f"depth arm={arm} bucket={bucket} {fmt(cell(subset))}")

    # Decision 12 (b) — as-treated, the combined arm only: the recency arm has
    # no evidence to have been treated with.
    for state in ("evidence", "no_evidence", "marker_false", "no_meal_record"):
        subset = [r for r in by_arm.get(COMBINED_ARM, []) if r["as_treated"] == state]
        print(f"astreated state={state} {fmt(cell(subset))}")

    # Decision 13 — the required boundary-bleed partition of the combined arm.
    bleed = {}
    for state in ("adjacent", "non_adjacent", "unknown"):
        subset = [r for r in by_arm.get(COMBINED_ARM, []) if r["adjacency"] == state]
        bleed[state] = cell(subset)
        print(f"bleed state={state} {fmt(bleed[state])}")
    print(f"bleed_verdict={bleed_verdict(bleed, args.min_cell)} min_cell={args.min_cell}")

    # The confound stated as data rather than prose: if the arms do not overlap
    # in time, any difference between them carries the corpus's growth as well
    # as the ordering's effect, and the depth strata above are the only cut that
    # separates the two.
    for arm in ARMS:
        subset = by_arm.get(arm, [])
        stamps = [r["created_at_ms"] for r in subset]
        depths = sorted(r["recency_depth"] for r in subset)
        median = depths[len(depths) // 2] if depths else None
        print(f"confound arm={arm} first={day(min(stamps)) if stamps else 'na'} "
              f"last={day(max(stamps)) if stamps else 'na'} "
              f"median_depth={median if median is not None else 'na'}")


def bleed_verdict(bleed, min_cell):
    """Does the partition say bleed is HURTING?

    The mitigation task fires on one shape only: adjacent corrections hitting
    the shortlist while non-adjacent ones miss, which means what touches the
    food is crowding genuine confusions out of the five slots. The opposite
    shape closes that task as no-change-needed. Anything measured on cells this
    small is neither.
    """
    adjacent, non_adjacent = bleed["adjacent"], bleed["non_adjacent"]
    if adjacent["n"] < min_cell or non_adjacent["n"] < min_cell:
        return "insufficient"
    if adjacent["rate"] > non_adjacent["rate"]:
        return "bleed_hurting"
    return "bleed_not_hurting"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", type=Path,
                    help="device pull / archive .sqlite, or a corrections .jsonl")
    ap.add_argument("--bundles", type=Path,
                    help="directory of capture bundles, for the adjacency cut")
    ap.add_argument("--bundle-window-ms", type=int, default=60_000,
                    help="how long after a bundle its meal record may be written")
    ap.add_argument("--min-cell", type=int, default=10,
                    help="rows a partition cell needs before it carries a verdict")
    ap.add_argument("--json", type=Path, help="write the annotated rows here")
    args = ap.parse_args()

    rows, meals = load(args.inputs)
    relabels = [row for row in rows if row["class_corrected"]]
    annotate_recency(relabels)
    annotate_as_treated(relabels, meals)

    bundles = load_bundles(args.bundles) if args.bundles else []
    matched = match_bundles(meals, bundles, args.bundle_window_ms) if bundles else {}
    annotate_adjacency(relabels, matched)

    report(rows, relabels, meals, matched, args)

    if args.json:
        args.json.write_text(json.dumps({
            "relabels": relabels,
            "matched_bundles": {k: v["path"].name for k, v in matched.items()},
        }, indent=2))


if __name__ == "__main__":
    main()

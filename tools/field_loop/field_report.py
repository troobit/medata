#!/usr/bin/env python3
"""The alignment report: is the gap shrinking, or am I just hoping? (Req 6)

Output follows `tools/shortlist_hit_rate.py`: `key=value` lines, every figure
beside the cell count it was computed over, and `insufficient` rather than a
number below `--min-cell`. On a corpus this size that is not decoration — a
rate over three captures is not a verdict, and a report that renders one as
though it were is worse than no report.

Four things this deliberately refuses to do:

* **Pool trained-on captures into the evaluation set** (6.4). `index.sqlite`
  marks each capture `training_used`; those rows are dropped and BOTH set
  sizes are printed, so the metric cannot be inflated by evaluating on what
  the model was fitted to.
* **Attribute a `-dirty` build stamp** (6.2). A dirty stamp names no commit, so
  those captures are bucketed `unattributable` rather than credited to the
  commit they were nearly built from.
* **Call a stated value ground truth** (6.5). Every stated figure is labelled
  `developer_stated`; the weighed surface is `benchmark_meals`, and it is not
  this report's input.
* **Report an absolute band as the target** (6.3). The target is directional:
  per-food trends carry a non-decrease flag into the verdict, and nothing here
  claims a pass mark.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    __package__ = "field_loop"

from . import causes, clusters, config, corpus  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
DIRTY_MARKER = "-dirty"
UNATTRIBUTABLE = "unattributable"

# The two committed artifacts whose ordered content hash identifies one bake.
DB_ARTIFACTS = ("MedataCore/Sources/Foods/Resources/cofid_db.sqlite",
                "MedataCore/Sources/Foods/Resources/afcd_db.sqlite")


# ------------------------------------------------------------------ formatting

def cell(values: list, min_cell: int) -> str:
    """A figure and its cell count, or `insufficient` and its cell count."""
    if len(values) < min_cell:
        return "value=insufficient n=%d" % len(values)
    return "value=%.4f n=%d" % (sum(values) / len(values), len(values))


def rate(hits: int, total: int, min_cell: int) -> str:
    if total < min_cell:
        return "value=insufficient n=%d" % total
    return "value=%.4f n=%d" % (hits / total, total)


# -------------------------------------------------------------- segmentation

def capture_mode(row) -> str:
    """Req 6.6: LiDAR/two-view crossed with card presence.

    Both halves are reported even when one is unknown — the deferred
    estimation-path decision (Decision 13) needs an evidence base covering both
    modes, and silently folding unknown-card captures into the card-absent
    bucket would corrupt exactly the comparison it exists for.
    """
    path = row["capture_mode"] or "unknown"
    scale = row["scale_source"] or "unknown"
    card = "card" if "card" in scale.lower() else (
        "no_card" if scale != "unknown" else "card_unknown")
    return "%s/%s" % (path, card)


def build_bucket(build_stamp) -> str:
    if not build_stamp:
        return UNATTRIBUTABLE
    if DIRTY_MARKER in build_stamp:
        # The stamp names no commit, so nothing downstream can say which loop
        # fixes this binary contained. Field deploys archive the working-tree
        # diff beside the stamp so the build stays reconstructable; the metric
        # still refuses to attribute it.
        return UNATTRIBUTABLE
    return build_stamp


def commit_of(build_stamp):
    """The short SHA a clean build stamp names, or None."""
    if not build_stamp or DIRTY_MARKER in build_stamp:
        return None
    return build_stamp.split("-")[0]


def db_hash_at(commit, repo_root=REPO_ROOT, runner=subprocess.run):
    """SHA-256 of the two committed sqlite artifacts, as an ORDERED whole.

    The pair identifies one bake rather than two independently-swappable
    files — the same definition `DiagnoseRun.contentSHA256` uses on the Swift
    side, so a hash computed here and one computed there mean the same thing.
    """
    import hashlib

    if not commit:
        return None
    digest = hashlib.sha256()
    for artifact in DB_ARTIFACTS:
        result = runner(["git", "show", "%s:%s" % (commit, artifact)],
                        cwd=str(repo_root), capture_output=True)
        if result.returncode != 0:
            return None
        digest.update(result.stdout)
    return digest.hexdigest()


def fixes_in_build(commit, loop_branch, repo_root=REPO_ROOT, runner=subprocess.run):
    """Which loop-branch fixes a build contains (Req 6.2).

    Derived, not recorded: `git merge-base --is-ancestor <fix commit> <build
    commit>` is the only honest answer to "was this fix in that binary", and it
    stays correct through rebases and merges that a recorded list would not.
    """
    listing = runner(["git", "log", "--format=%H%x00%s", loop_branch],
                     cwd=str(repo_root), capture_output=True, text=True)
    if listing.returncode != 0:
        return []
    contained = []
    for line in listing.stdout.splitlines():
        sha, _, subject = line.partition("\x00")
        if not sha:
            continue
        check = runner(["git", "merge-base", "--is-ancestor", sha, commit],
                       cwd=str(repo_root), capture_output=True)
        if check.returncode == 0:
            contained.append(subject)
    return contained


# ----------------------------------------------------------------- the report

def load_rows(conn, cycle=None) -> list:
    """Annotated captures joined to their latest diagnosis."""
    sql = """
        SELECT c.stem, c.capture_mode, c.scale_source, c.build_stamp,
               c.model_version, c.db_hash, c.training_used, c.detected_classes,
               c.timestamp_ms, d.note_id, d.cause, d.replay_status,
               d.replay_version_skew, d.replay_delta_g, d.evidence_json,
               d.cluster_id, d.cycle, n.carbs_g, n.snapshot_json
        FROM diagnoses d
        JOIN captures c ON c.stem = d.stem
        JOIN notes n ON n.id = d.note_id
    """
    params = []
    if cycle is not None:
        sql += " WHERE d.cycle <= ?"
        params.append(cycle)
    sql += " ORDER BY c.timestamp_ms, d.note_id"
    return [dict(r) for r in conn.execute(sql, params)]


def evaluation_split(rows) -> tuple:
    """(evaluated, excluded) — Req 6.4, with both sizes printed by the caller."""
    evaluated = [r for r in rows if not r["training_used"]]
    excluded = [r for r in rows if r["training_used"]]
    return evaluated, excluded


def evaluation_cells(rows) -> dict:
    """(class, capture mode) -> count, the cells the eval floor guards.

    Derivation consults this before consuming a capture: a training appetite
    that starves a cell would make the metric go `insufficient` through the
    loop's own doing, which is the one way a directional target can be gamed
    without anyone lying.
    """
    cells = {}
    for row in rows:
        if row["training_used"]:
            continue
        for food in (row["detected_classes"] or "").split(","):
            if not food:
                continue
            key = (food, capture_mode(row))
            cells[key] = cells.get(key, 0) + 1
    return cells


def class_selection_error(rows, min_cell: int) -> dict:
    """Rate at which the pipeline's classes disagreed with the reference read.

    Only captures whose diagnosis actually carries a reference disagreement
    can answer this; the rest are absent from the denominator rather than
    counted as correct.
    """
    by_mode = {}
    for row in rows:
        evidence = json.loads(row["evidence_json"] or "{}")
        if "reference_class_disagreement" not in evidence \
                and row["cause"] not in (causes.WRONG_CLASS, causes.ABSENT_FROM_PALETTE,
                                         causes.WITHIN_REPLAY_NOISE,
                                         causes.WRONG_DENSITY, causes.WRONG_SCALE,
                                         causes.WRONG_MASK):
            continue
        bucket = by_mode.setdefault(capture_mode(row), [0, 0])
        bucket[1] += 1
        if row["cause"] in (causes.WRONG_CLASS, causes.ABSENT_FROM_PALETTE):
            bucket[0] += 1
    return {mode: rate(hits, total, min_cell)
            for mode, (hits, total) in sorted(by_mode.items())}


def quantity_gap(rows, min_cell: int) -> dict:
    """Absolute carbohydrate gap against the DEVELOPER-STATED amount.

    Stated in the developer's own household terms and never converted here: the
    note text is not parsed on the Mac either, so what this measures is the gap
    against the structured `carbs_g` field the sheet offers beside the text.
    """
    by_mode = {}
    for row in rows:
        evidence = json.loads(row["evidence_json"] or "{}")
        gap = evidence.get("gap_g")
        if gap is None:
            continue
        by_mode.setdefault(capture_mode(row), []).append(abs(gap))
    return {mode: cell(values, min_cell) for mode, values in sorted(by_mode.items())}


def mask_consistency_by_cluster(rows, min_cell: int) -> dict:
    """The three pinned numbers, per cluster, averaged with cell counts."""
    by_cluster = {}
    for row in rows:
        by_cluster.setdefault(row["cluster_id"], []).append(row)

    agreements, ious, covs, sizes = [], [], [], []
    for group in by_cluster.values():
        sizes.append(len(group))
        evidence = [json.loads(r["evidence_json"] or "{}") for r in group]
        for key, sink in (("dominant_agreement", agreements),
                          ("mean_pairwise_iou", ious), ("carbs_cov", covs)):
            values = [e[key] for e in evidence if e.get(key) is not None]
            if values:
                sink.append(sum(values) / len(values))
    return {
        "dominant_agreement": cell(agreements, min_cell),
        "mean_pairwise_iou": cell(ious, min_cell),
        "carbs_cov": cell(covs, min_cell),
        "clusters": len(by_cluster),
        "cluster_sizes": sorted(sizes),
    }


def per_food_trend(rows, min_cell: int) -> dict:
    """Selection-error and mask-inconsistency trend per food, across builds.

    Req 6.3 wants direction, not a band: each food's earliest and latest build
    buckets are compared, and any NON-decrease is flagged for the verdict.
    Foods appearing under a single build have no trend and say so.
    """
    per_food = {}
    for row in rows:
        for food in (row["detected_classes"] or "").split(","):
            if not food:
                continue
            bucket = build_bucket(row["build_stamp"])
            if bucket == UNATTRIBUTABLE:
                continue
            per_food.setdefault(food, {}).setdefault(bucket, []).append(row)

    trends = {}
    for food, buckets in sorted(per_food.items()):
        if len(buckets) < 2:
            trends[food] = {"trend": "single_build", "flag": False,
                            "n": sum(len(v) for v in buckets.values())}
            continue
        ordered = sorted(buckets, key=lambda b: min(
            r["timestamp_ms"] or 0 for r in buckets[b]))
        first, last = buckets[ordered[0]], buckets[ordered[-1]]
        before = _error_share(first)
        after = _error_share(last)
        flag = after >= before
        trends[food] = {
            "trend": "%.4f->%.4f" % (before, after),
            "flag": flag,
            "n": len(first) + len(last),
            "insufficient": len(first) < min_cell or len(last) < min_cell,
        }
    return trends


def _error_share(group) -> float:
    bad = sum(1 for r in group
              if r["cause"] in (causes.WRONG_CLASS, causes.ABSENT_FROM_PALETTE,
                                causes.WRONG_MASK))
    return bad / len(group) if group else 0.0


def corpus_growth(conn) -> dict:
    """Req 8.7: is the corpus actually accumulating real-world coverage?"""
    captures = conn.execute("SELECT count(*) FROM captures").fetchone()[0]
    annotated = conn.execute(
        "SELECT count(DISTINCT stem) FROM notes WHERE stem IS NOT NULL").fetchone()[0]
    per_class = {}
    for row in conn.execute("SELECT detected_classes FROM captures"):
        for food in (row["detected_classes"] or "").split(","):
            if food:
                per_class[food] = per_class.get(food, 0) + 1
    return {"captures": captures, "annotated": annotated,
            "annotated_share": round(annotated / captures, 4) if captures else 0.0,
            "per_class": per_class}


def report(conn, settings, cycle=None, out=print) -> dict:
    min_cell = config.get(settings, "min_cell")
    rows = load_rows(conn, cycle)
    evaluated, excluded = evaluation_split(rows)

    out("report labelling=developer_stated "
        "note='stated values are the developer's estimates, not ground truth; "
        "the weighed surface is benchmark_meals'")
    out("report evaluation_set n=%d training_used_excluded n=%d"
        % (len(evaluated), len(excluded)))
    out("report min_cell=%d" % min_cell)

    for mode, figure in class_selection_error(evaluated, min_cell).items():
        out("class_selection_error mode=%s %s" % (mode, figure))
    for mode, figure in quantity_gap(evaluated, min_cell).items():
        out("quantity_gap_g mode=%s %s developer_stated=true" % (mode, figure))

    consistency = mask_consistency_by_cluster(evaluated, min_cell)
    out("mask_consistency dominant_agreement %s" % consistency["dominant_agreement"])
    out("mask_consistency mean_pairwise_iou %s" % consistency["mean_pairwise_iou"])
    out("mask_consistency carbs_cov %s" % consistency["carbs_cov"])
    out("mask_consistency clusters=%d sizes=%s"
        % (consistency["clusters"], ",".join(str(s) for s in consistency["cluster_sizes"])))

    buckets = {}
    for row in evaluated:
        key = (build_bucket(row["build_stamp"]), row["model_version"] or "unknown",
               row["db_hash"] or "unknown")
        buckets[key] = buckets.get(key, 0) + 1
    for (stamp, model, db_hash), count in sorted(buckets.items()):
        out("segment build=%s model=%s db_hash=%s n=%d"
            % (stamp, model, (db_hash or "unknown")[:12], count))

    flagged = []
    for food, trend in per_food_trend(evaluated, min_cell).items():
        out("per_food food=%s trend=%s n=%d flag_non_decrease=%s%s"
            % (food, trend["trend"], trend["n"], str(trend["flag"]).lower(),
               " insufficient=true" if trend.get("insufficient") else ""))
        if trend["flag"]:
            flagged.append(food)

    growth = corpus_growth(conn)
    out("corpus_growth captures=%d annotated=%d annotated_share=%.4f"
        % (growth["captures"], growth["annotated"], growth["annotated_share"]))
    for food, count in sorted(growth["per_class"].items()):
        out("corpus_coverage food=%s n=%d" % (food, count))

    cells = evaluation_cells(evaluated)
    floor = config.get(settings, "eval_floor_per_cell")
    starved = sorted(k for k, v in cells.items() if v < floor)
    out("eval_floor per_cell=%d cells=%d below_floor=%d"
        % (floor, len(cells), len(starved)))
    for food, mode in starved:
        out("eval_floor_below food=%s mode=%s n=%d" % (food, mode, cells[(food, mode)]))

    return {"evaluated": len(evaluated), "training_used_excluded": len(excluded),
            "non_decrease_flagged": flagged, "cells": cells,
            "corpus_growth": growth}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--corpus")
    ap.add_argument("--cycle", type=int)
    ap.add_argument("--config")
    ap.add_argument("--min-cell", type=int)
    ap.add_argument("--out", type=Path, help="also write the report here")
    args = ap.parse_args(argv)

    root = Path(args.corpus) if args.corpus else corpus.corpus_root()
    conn = corpus.open_index(root)
    settings = config.load(args.config)
    if args.min_cell is not None:
        settings["min_cell"] = args.min_cell

    lines = []

    def emit(line):
        lines.append(line)
        print(line)

    report(conn, settings, args.cycle, out=emit)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text("\n".join(lines) + "\n")
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Flatten the corpus into one learnable table per capture.

The estimation calculus is recorded per outcome as a JSON blob in
`outcomes.measurements_json` — plane candidates and inliers, the plane
reference and residual, the card candidate count, both tilts, region growth,
volume, sigma. Everything a later calibration or training pass would want is
already there, and none of it is reachable: it is one opaque TEXT column that
`field_report` and `derive_dataset` do not read, keyed to a table they select
against by stem.

This emits one JSONL record per capture, joining the capture, its outcome, the
corrections applied to it and any weighed truth, with the calculus promoted to
named fields. Refused captures are included and are the point: a two-view
refusal is the evidence the non-LiDAR path is measured on, and it is the row
that carries the tilts and the card candidate count.

SENTINELS ARE NOT MEASUREMENTS. `SupportPlaneFitStats` documents `-1` as "the
fit refused BEFORE residual was computed" and returns a default-constructed
value on an unconditional refusal, so a refused row reads
`planeCandidateCount=0 planeInlierCount=0 planeResidualMm=-1` without anything
having run. Exported as-is those become zeros and a negative millimetre that a
fit would never produce, and any model trained over them learns from padding.
Every such field is emitted as null, with `placeholders` naming which ones were
suppressed, so the distinction survives the export instead of being an
invariant someone has to remember.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import corpus  # noqa: E402

# Calculus fields promoted from measurements_json, and the value that means
# "not measured" rather than "measured as this".
SENTINELS = {
    "planeResidualMm": (-1, -1.0),
    "planeCandidateCount": (0,),
    "planeCandidatePlaneCount": (0,),
    "planeInlierCount": (0,),
    "planeSupportingSectors": (0,),
    "cardCandidateCount": (),          # 0 is a real observation: no candidate found
    "nadirTiltDeg": (),
    "obliqueTiltDeg": (),
    "foodRegionCoveragePercent": (),
    "planeRingMedianMm": (),
}
SCALAR_FIELDS = tuple(SENTINELS) + ("capturePath", "planeReference", "scaleSource",
                                    "degradedReason", "modelVersion")
NESTED_FIELDS = ("volume", "decomposition", "sigma", "regionGrowth", "card",
                 "twoViewReconciliation", "segmentationNadir", "failure")


def _promote(measurements: dict) -> tuple[dict, list]:
    """Named calculus fields, plus the list of sentinels suppressed to null."""
    out, placeholders = {}, []
    for key in SCALAR_FIELDS:
        value = measurements.get(key)
        if value is not None and value in SENTINELS.get(key, ()):
            out[key], _ = None, placeholders.append(key)
        else:
            out[key] = value
    for key in NESTED_FIELDS:
        out[key] = measurements.get(key)
    return out, placeholders


def records(root: Path):
    conn = corpus.open_index(root)
    try:
        truth = {}
        for row in conn.execute(
            "SELECT o.id AS outcome_id, b.truth_carbs_g, b.fidelity, b.items, b.name "
            "FROM outcomes o JOIN benchmark_meals b ON b.id = o.benchmark_meal_id"
        ):
            truth[row["outcome_id"]] = {
                "truth_carbs_g": row["truth_carbs_g"], "fidelity": row["fidelity"],
                "benchmark_name": row["name"], "items": json.loads(row["items"] or "[]"),
            }

        corrected = {}
        for row in conn.execute(
            "SELECT outcome_id, count(*) n, sum(class_corrected) cls, "
            "sum(rejected) rej, sum(amount_corrected) amt FROM corrections "
            "GROUP BY outcome_id"
        ):
            corrected[row["outcome_id"]] = {
                "corrections": row["n"], "class_corrected": row["cls"],
                "rejected": row["rej"], "amount_corrected": row["amt"],
            }

        for row in conn.execute(
            "SELECT c.*, o.id AS outcome_id, o.outcome AS outcome_state, o.failure, "
            "o.meal_id, o.measurements_json, o.protected "
            "FROM captures c LEFT JOIN outcomes o "
            "ON (o.timestamp_ms || '-' || o.outcome) = c.stem ORDER BY c.stem"
        ):
            try:
                measurements = json.loads(row["measurements_json"] or "{}")
            except (ValueError, TypeError):
                measurements = {}
            calculus, placeholders = _promote(measurements)
            fixture = root / "captures" / ("%s.fixture" % row["stem"])
            yield {
                "stem": row["stem"],
                "pull_id": row["pull_id"],
                "timestamp_ms": row["timestamp_ms"],
                "outcome": row["outcome"],
                "outcome_state": row["outcome_state"],
                "failure": row["failure"],
                "capture_mode": row["capture_mode"],
                "scale_source": row["scale_source"],
                "build_stamp": row["build_stamp"],
                "model_version": row["model_version"],
                "db_edition": row["db_edition"],
                "detected_classes": [c for c in (row["detected_classes"] or "").split(",") if c],
                "slimmed": bool(row["slimmed"]),
                "training_used": bool(row["training_used"]),
                "protected": bool(row["protected"]),
                # Replay is only possible where the bundle survived the discard.
                "fixture_present": fixture.exists(),
                "meal_id": row["meal_id"],
                "outcome_id": row["outcome_id"],
                "calculus": calculus,
                "placeholders": placeholders,
                "truth": truth.get(row["outcome_id"]),
                "corrections": corrected.get(row["outcome_id"]),
            }
    finally:
        conn.close()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--corpus", help="override the resolved corpus root")
    ap.add_argument("--out", help="write JSONL here instead of stdout")
    args = ap.parse_args(argv)

    root = corpus.ensure_layout(Path(args.corpus) if args.corpus else corpus.corpus_root())
    rows = list(records(root))

    handle = open(args.out, "w") if args.out else sys.stdout
    try:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")
    finally:
        if args.out:
            handle.close()

    # Counts to stderr so stdout stays a clean stream when piped.
    by_mode = {}
    for row in rows:
        key = (row["capture_mode"], row["scale_source"] or "none")
        by_mode[key] = by_mode.get(key, 0) + 1
    print("export rows=%d truthed=%d replayable=%d suppressed_placeholders=%d"
          % (len(rows), sum(1 for r in rows if r["truth"]),
             sum(1 for r in rows if r["fixture_present"]),
             sum(len(r["placeholders"]) for r in rows)), file=sys.stderr)
    for (mode, source), n in sorted(by_mode.items()):
        print("export mode=%s scale=%s n=%d" % (mode, source, n), file=sys.stderr)
    if args.out:
        print("export out=%s" % args.out, file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

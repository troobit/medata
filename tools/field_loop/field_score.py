#!/usr/bin/env python3
"""Score the weighed field captures end to end: derive, `accuracy`, `calibrate`.

`make field-score` runs this. It derives the weighed set into one directory per
segmenter checkpoint (`derive_dataset.derive_calibration`), runs HarnessCLI
`accuracy` and `calibrate` over each group with the group's run summary, and
prints one line per capture, the set's error and each group's β result.

Every figure is the harness's own: this module reads the JSON the two
subcommands write and only lays it out and averages across groups, which no
single harness run can do because the loader takes one checkpoint at a time.

Two readings are printed for each capture. "As reviewed" is the meal at the
classes the review named — the figure the user ends up with, and the one
`calibrate` fits. "As labelled" is the segmenter's own classes, which is what
`accuracy` reported before the review was applied.
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

from . import corpus, derive_dataset  # noqa: E402

PATH_LABEL = {"single_view_lidar": "1-view", "two_view_sfs": "2-view"}


def run_harness(harness: str, subcommand: str, directory: Path,
                checkpoint: str) -> dict:
    """One HarnessCLI subcommand over one group; its JSON, its stderr kept.

    `accuracy` exits 1 when the set misses the MAPE bar, after writing its
    report — a verdict, not a failure — so the report's presence is what
    decides whether the run worked.
    """
    output = directory / ("%s.json" % subcommand)
    if output.exists():
        output.unlink()
    proc = subprocess.run(
        [harness, subcommand, "--fixtures-dir", str(directory),
         "--checkpoint-sha256", checkpoint,
         "--ingest-summary", str(directory / "run_summary.json"),
         "--output", str(output)],
        capture_output=True, text=True)
    log = directory / ("%s.log" % subcommand)
    log.write_text(proc.stdout + proc.stderr)
    if not output.exists():
        raise SystemExit("field-score: %s failed for %s (exit %d); see %s"
                         % (subcommand, checkpoint, proc.returncode, log))
    return json.loads(output.read_text())


def _total(values) -> float:
    return sum((values or {}).values())


def _percent(predicted: float, truth: float):
    return (predicted - truth) / truth * 100 if truth > 0 else None


def capture_row(checkpoint: str, fixture_id: str, row: dict,
                fixture: dict) -> dict:
    """One capture's figures, from its accuracy row and its derived truth."""
    truth = fixture["truth"]
    review = row.get("review") or {}
    labelled = review.get("labelledCarbsG", row["predictedCarbsG"])
    mass = _total(row.get("perClassMassG"))
    truth_g = _total(truth["class_mass_g"])
    return {
        "fixture": fixture_id,
        "checkpoint": checkpoint,
        "path": PATH_LABEL.get(row["capturePath"], row["capturePath"]),
        "plane": row.get("supportPlaneReference") or "none",
        "volumes": row.get("perClassVolumesCm3") or {},
        "relabelled": review.get("relabelled") or {},
        "rejected": {c: v for c, v in (review.get("labelledVolumesCm3") or {}).items()
                     if c in (review.get("rejected") or [])},
        "volume": _total(row.get("perClassVolumesCm3")),
        "mass": mass,
        "carbs": row["predictedCarbsG"],
        "labelled_carbs": labelled,
        "truth_g": truth_g,
        "truth_carbs": truth["total_carbs_g"],
        "truth_classes": sorted(truth["class_mass_g"]),
        "mass_error": _percent(mass, truth_g),
        "carbs_error": _percent(row["predictedCarbsG"], truth["total_carbs_g"]),
        "labelled_error": _percent(labelled, truth["total_carbs_g"]),
    }


def classes_text(row: dict) -> str:
    """The reviewed classes, each with the label it replaced and its volume."""
    origin = {}
    for labelled, reviewed in sorted(row["relabelled"].items()):
        origin.setdefault(reviewed, []).append(labelled)
    parts = []
    for name, volume in sorted(row["volumes"].items(), key=lambda kv: -kv[1]):
        text = "%s %.1f" % (name, volume)
        if name in origin:
            text += " (was %s)" % "+".join(origin[name])
        parts.append(text)
    for name, volume in sorted(row["rejected"].items()):
        parts.append("%s %.1f rejected" % (name, volume))
    return "; ".join(parts) or "no food"


def _signed(value) -> str:
    return "n/a" if value is None else "%+.1f%%" % value


def aggregate(rows: list, predicted: str, truth: str) -> tuple:
    """(MAPE %, MAE) over the rows carrying truth, as `AccuracyHarness` scores."""
    scored = [r for r in rows if r[truth] > 0]
    if not scored:
        return None, None
    mape = sum(abs(r[predicted] - r[truth]) / r[truth] for r in scored) \
        / len(scored) * 100
    mae = sum(abs(r[predicted] - r[truth]) for r in scored) / len(scored)
    return mape, mae


def beta_lines(checkpoint: str, artifact: dict, rows: list) -> list:
    """What `calibrate` baked for one group, or why it baked nothing."""
    classes = artifact.get("classes") or {}
    floor = artifact.get("lineage", {}).get("effective_sample_min", 30)
    baked = {name: c for name, c in classes.items() if c["status"] == "calibrated"}
    lines = []
    if baked:
        for name, c in sorted(baked.items()):
            lines.append("beta %s: %s = %.3f (effective %d, SE %s, %s)"
                         % (checkpoint, name, c["beta"], c["effective_sample"],
                            "n/a" if c.get("standard_error") is None
                            else "%.3f" % c["standard_error"], c["provenance"]))
    elif classes:
        lines.append("beta %s: none baked — %s" % (checkpoint, "; ".join(
            "%s has %d admitted plate(s), the floor is %d"
            % (name, c["effective_sample"], floor)
            for name, c in sorted(classes.items()))))
    else:
        lines.append("beta %s: none baked — no plate passed the gates" % checkpoint)

    by_id = {r["fixture"]: r for r in rows}
    summary = artifact.get("run_summary") or {}
    tau = artifact.get("lineage", {}).get("tau_purity", 0.9)
    for fixture_id in summary.get("purity_dropped", []):
        row = by_id.get(fixture_id)
        if row is None:
            lines.append("  purity dropped %s" % fixture_id)
            continue
        dominant = row["truth_classes"][0] if row["truth_classes"] else "none"
        purity = row["volumes"].get(dominant, 0.0) / row["volume"] \
            if row["volume"] > 0 else 0.0
        lines.append("  purity dropped %s: reviewed %s; truth %s; purity %.2f < %.2f"
                     % (fixture_id, classes_text(row),
                        "+".join(row["truth_classes"]) or "none", purity, tau))
    for fixture_id in summary.get("support_plane_reference_excluded", []):
        plane = by_id[fixture_id]["plane"] if fixture_id in by_id else "unknown"
        lines.append("  reference excluded %s: plane %s; beta is fitted on %s"
                     % (fixture_id, plane,
                        artifact.get("support_plane_reference", "foodSupport")))
    for fixture_id in summary.get("plane_fit_skipped", []):
        lines.append("  replay failed %s (see calibrate.log)" % fixture_id)
    return lines


def score(harness: str, conn, root, out) -> list:
    """Derive, replay, and the printed report as a list of lines."""
    document = derive_dataset.derive_calibration(conn, root, out)
    lines = ["field-score: %d weighed capture(s) in %d checkpoint group(s), out=%s"
             % (document["ingested"],
                sum(1 for g in document["groups"].values() if g["ingested"]),
                document["out"])]
    for reason, stems in sorted(document["skipped"].items()):
        for stem in stems:
            lines.append("skipped %s: %s" % (stem, reason))

    rows, betas = [], []
    for checkpoint, group in sorted(document["groups"].items()):
        if not group["ingested"]:
            continue
        directory = Path(group["dir"])
        fixtures = json.loads(
            (directory / "run_summary.json").read_text())["fixtures"]
        accuracy = run_harness(harness, "accuracy", directory, checkpoint)
        replayed = {r["fixtureID"] for r in accuracy["rows"]}
        group_rows = [capture_row(checkpoint, r["fixtureID"], r,
                                  fixtures[r["fixtureID"]])
                      for r in accuracy["rows"] if r["fixtureID"] in fixtures]
        for fixture_id in sorted(set(fixtures) - replayed):
            lines.append("not replayed %s (see %s/accuracy.log)"
                         % (fixture_id, directory))
        rows.extend(group_rows)
        artifact = run_harness(harness, "calibrate", directory, checkpoint)
        betas.extend(beta_lines(checkpoint, artifact, group_rows))

    lines.append("")
    row_format = "%-21s  %-12s  %-6s  %-11s  %7s  %15s  %7s  %15s  %7s  %14s  %s"
    lines.append(row_format % (
        "capture", "checkpoint", "path", "plane", "vol cm3", "mass g / truth",
        "err", "carbs g / truth", "err", "as labelled", "classes after review (cm3)"))
    for r in sorted(rows, key=lambda r: r["fixture"]):
        lines.append(row_format % (
            r["fixture"], r["checkpoint"], r["path"], r["plane"],
            "%.1f" % r["volume"],
            "%.1f / %.1f" % (r["mass"], r["truth_g"]), _signed(r["mass_error"]),
            "%.1f / %.1f" % (r["carbs"], r["truth_carbs"]), _signed(r["carbs_error"]),
            "%.1f %s" % (r["labelled_carbs"], _signed(r["labelled_error"])),
            classes_text(r)))

    lines.append("")
    for label, predicted, truth, unit in (
            ("carbs as reviewed", "carbs", "truth_carbs", "g"),
            ("mass as reviewed", "mass", "truth_g", "g"),
            ("carbs as labelled", "labelled_carbs", "truth_carbs", "g")):
        mape, mae = aggregate(rows, predicted, truth)
        if mape is None:
            lines.append("set %s: nothing scored" % label)
        else:
            lines.append("set %s (n=%d): MAPE %.1f%%  MAE %.1f %s"
                         % (label, len(rows), mape, mae, unit))
    lines.append("")
    lines.extend(betas)
    return lines


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--harness", required=True, help="path to a built HarnessCLI")
    ap.add_argument("--out", required=True,
                    help="directory for the derived groups and the harness output")
    ap.add_argument("--corpus")
    args = ap.parse_args(argv)

    root = Path(args.corpus) if args.corpus else corpus.corpus_root()
    conn = corpus.open_index(root)
    try:
        lines = score(args.harness, conn, root, Path(args.out))
    finally:
        conn.close()
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

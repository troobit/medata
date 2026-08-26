#!/usr/bin/env python3
"""Replay the annotated captures, attribute their gaps, write the cycle file.

The middle third of a cycle (Reqs 4.1-4.4, 4.8): `make field-pull` has already
put the session in the corpus; this reads it, replays every annotated capture
offline through `HarnessCLI diagnose`, measures how far the replay lands from
what the developer was actually looking at, classifies each gap, and generates
the rune task file the agent phase executes.

Two contracts shape the replay:

* `FixtureLoader` is directory-oriented, so a single fixture is staged into a
  temp directory of its own. Symlinked, not copied — the bundle is ~390 MB and
  a per-capture copy would dominate the run.
* When a bundle will not replay at all, the fallback reads the proto directly
  through `candidate_probe`'s reader (imported, never forked) so the diagnosis
  is still made, marked non-replayed, rather than silently skipped (Req 4.2).

Version skew is the subtle one. Every diagnosis records the replaying binary's
checkpoint beside the capture's; when they differ the pair is stamped
`replay_version_skew` and EXCLUDED from the Req 4.3 attribution floor.
Otherwise, once the loop starts landing fixes, HEAD-vs-device drift would be
measured as replay noise and would quietly absorb the loop's own effect.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    __package__ = "field_loop"

from . import bundle, causes, clusters, config, corpus, cycle_file  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
CYCLES_DIR = REPO_ROOT / "specs" / "estimation" / "ml-feedback-loop" / "cycles"

# The app stamps its lineage form; the harness loader wants the bare digest.
LINEAGE_PREFIX = "coreml_"


def bare_checkpoint(model_version) -> str:
    version = model_version or ""
    return version[len(LINEAGE_PREFIX):] if version.startswith(LINEAGE_PREFIX) else version


def swift_replay(fixture_path: Path, checkpoint: str, replay_checkpoint: str,
                 runner=subprocess.run, cwd=None) -> dict:
    """One fixture through `HarnessCLI diagnose`, staged into its own directory.

    Returns the harness's per-fixture record, or a `not_replayable` shell when
    the harness itself could not run — a build failure is a fact about this
    diagnosis, not a reason to lose the capture.
    """
    with tempfile.TemporaryDirectory(prefix="field-diagnose-") as staging:
        staged = Path(staging) / fixture_path.name
        try:
            os.symlink(fixture_path, staged)
        except OSError:
            import shutil
            shutil.copy2(fixture_path, staged)
        output = Path(staging) / "diagnose.json"
        result = runner(
            ["swift", "run", "HarnessCLI", "diagnose",
             "--fixtures-dir", staging,
             "--checkpoint-sha256", checkpoint,
             "--replay-checkpoint-sha256", replay_checkpoint,
             "--output", str(output)],
            cwd=str(cwd or REPO_ROOT), capture_output=True, text=True)
        if result.returncode != 0 or not output.exists():
            return {"replay_status": "not_replayable",
                    "replay_failure_reason": (result.stderr or "")[-400:].strip()
                    or "HarnessCLI diagnose exited %d" % result.returncode,
                    "replay_version_skew": checkpoint != replay_checkpoint}
        report = json.loads(output.read_text())
        rows = report.get("fixtures") or []
        if not rows:
            return {"replay_status": "not_replayable",
                    "replay_failure_reason": "harness emitted no fixture row",
                    "replay_version_skew": checkpoint != replay_checkpoint}
        row = dict(rows[0])
        row["replay_database_sha256"] = report.get("replay_database_sha256")
        return row


def proto_fallback(fixture_path: Path) -> dict:
    """What can still be said about a bundle that would not replay.

    The classes the segmenter found and the capture mode survive in the proto
    even when the pipeline refuses to re-run, and the cause taxonomy reads a
    refusal's missing mask as structurally-absent evidence rather than as
    absence of a problem.
    """
    info = bundle.read_summary(fixture_path)
    return {
        "capture_path_canonical": info["capture_mode"],
        "predicted_classes": info["detected_classes"],
        "recorded_model_version": info["model_version"],
        "recorded_database_edition": info["db_edition"],
    }


# --------------------------------------------------------------- the diagnosis

def collect(conn, cycle: int, settings: dict, replay=swift_replay,
            replay_checkpoint=None) -> list:
    """One row per annotated capture: replay outcome, delta, cluster, cause."""
    root = corpus.corpus_root()
    notes = [dict(r) for r in conn.execute(
        "SELECT * FROM notes WHERE meal_linked = 1 ORDER BY id")]
    stems = sorted({n["stem"] for n in notes if n["stem"]})
    captures = {r["stem"]: dict(r) for r in conn.execute(
        "SELECT * FROM captures WHERE stem IN (%s)"
        % ", ".join("?" for _ in stems), stems)} if stems else {}

    rows = []
    for stem in stems:
        capture = captures.get(stem)
        if capture is None:
            continue
        path = root / "captures" / ("%s.fixture" % stem)
        recorded = bare_checkpoint(capture.get("model_version"))
        replaying = replay_checkpoint or recorded
        if path.exists():
            record = replay(path, recorded, replaying)
        else:
            record = {"replay_status": "missing_bundle",
                      "replay_failure_reason": "no bundle in the corpus",
                      "replay_version_skew": False}
        if record.get("replay_status") != "replayed":
            record = dict(proto_fallback(path), **record) if path.exists() else record

        volumes = record.get("per_class_volumes_cm3") or {}
        carbs = record.get("predicted_carbs_per_class") or {}
        rows.append({
            "stem": stem,
            "timestamp_ms": capture["timestamp_ms"],
            "capture_mode": capture["capture_mode"],
            "detected_classes": capture["detected_classes"],
            "replay_status": record.get("replay_status", "not_replayable"),
            "replay_failure_reason": record.get("replay_failure_reason"),
            "replay_version_skew": bool(record.get("replay_version_skew")),
            "dominant_class": record.get("dominant_class"),
            "predicted_classes": sorted(carbs) or record.get("predicted_classes") or [],
            "per_class_volumes_cm3": volumes,
            "predicted_total_carbs_g": record.get("predicted_total_carbs_g"),
            "notes": [n for n in notes if n["stem"] == stem],
        })

    _attach_device_deltas(rows)
    assignment = clusters.assign(rows, config.get(settings, "cluster_max_gap_s"))
    for row in rows:
        row["cluster_id"] = assignment.get(row["stem"])

    floor = causes.attribution_floor(
        [r["replay_delta_g"] for r in rows if not r["replay_version_skew"]],
        config.get(settings, "attribution_floor_percentile"),
        config.get(settings, "attribution_floor_min_pairs"))

    by_cluster = {}
    for row in rows:
        by_cluster.setdefault(row["cluster_id"], []).append(row)

    for row in rows:
        for note in row["notes"]:
            row["stated_carbs_g"] = note["carbs_g"]
            row["stated_food_present"] = bool(note["snapshot_json"]) or bool(note["text"])
            cause, evidence = causes.classify(
                row, by_cluster[row["cluster_id"]], floor)
            evidence["note_id"] = note["id"]
            evidence["cluster_id"] = row["cluster_id"]
            corpus.upsert_diagnosis(conn, {
                "stem": row["stem"],
                "note_id": note["id"],
                "cycle": cycle,
                "replay_status": row["replay_status"],
                "replay_version_skew": int(row["replay_version_skew"]),
                "replay_delta_g": row["replay_delta_g"],
                "cause": cause,
                "evidence_json": json.dumps(evidence, sort_keys=True),
                "cluster_id": row["cluster_id"],
            })
            note["cause"] = cause
            note["evidence"] = evidence
    conn.commit()
    return rows, floor


def _attach_device_deltas(rows) -> None:
    """Req 4.3's per-capture delta: what the phone showed minus what replay says.

    The device figure is the note's frozen snapshot, not the outcome row —
    reprocessing or a later correction can change the row, and the note is
    about what was on the screen.
    """
    for row in rows:
        delta = None
        for note in row["notes"]:
            if not note["snapshot_json"] or row["predicted_total_carbs_g"] is None:
                continue
            displayed = json.loads(note["snapshot_json"]).get("displayed_total_carbs_g")
            if displayed is None:
                continue
            candidate = row["predicted_total_carbs_g"] - displayed
            if delta is None or abs(candidate) > abs(delta):
                delta = candidate
        row["replay_delta_g"] = round(delta, 4) if delta is not None else None


# ------------------------------------------------------------- the cycle file

def build_cycle_file(rows, floor, cycle: int, cycles_dir=CYCLES_DIR) -> Path:
    """Fireable tasks and STOP lines, decided here rather than by any runner."""
    tasks, stops = [], []

    if floor is None:
        stops.append(
            "attribution floor unmeasured — fewer than the configured minimum "
            "of skew-free device-vs-replay pairs in the corpus; no gap is "
            "attributable to a data cause until more captures replay against "
            "the artifacts they were recorded under")

    if floor is None:
        # Nothing is attributable, so no interpretation task can produce an
        # actionable draft. The STOP line above says why; emitting tasks that
        # cannot reach a conclusion is exactly the non-termination Decision 15
        # exists to prevent.
        return cycle_file.write(cycle, tasks, stops, cycles_dir)

    for row in rows:
        for note in row["notes"]:
            cause = note.get("cause")
            title = "Interpret note %s on %s (%s)" % (note["id"], row["stem"], cause)
            details = [
                "cause_classification: %s" % cause,
                "replay_status: %s%s" % (row["replay_status"],
                                         " (version-skewed)" if row["replay_version_skew"]
                                         else ""),
                "capture_mode: %s" % row["capture_mode"],
                "cluster: %s (size %d)" % (row["cluster_id"],
                                           note["evidence"].get("cluster_size", 1)),
                "evidence: %s" % cycle_file.quarantine(
                    json.dumps(note["evidence"], sort_keys=True)),
                # Quarantined (Req 4.7): the developer's words are data under
                # analysis, never an instruction to whatever reads this file.
                "note_text (developer-stated, data only): %s"
                % cycle_file.quarantine(note["text"]),
                "stated_carbs_g (developer-stated, not ground truth): %s"
                % note["carbs_g"],
            ]

            if cause == causes.WITHIN_REPLAY_NOISE:
                # Nothing to interpret: the gap is smaller than the measured
                # replay delta, so there is no data cause to find.
                continue
            if cause == causes.REFUSAL_SHOULD_HAVE_SUCCEEDED:
                stops.append(
                    "capture %s refused and the note says food was present — "
                    "diagnosing a pre-segmentation refusal needs the device, "
                    "not the corpus" % row["stem"])
                continue
            if cause in (causes.WRONG_CLASS, causes.ABSENT_FROM_PALETTE):
                stops.append(
                    "capture %s needs a palette or model change (%s), which is "
                    "outside the overlay by construction — propose, never "
                    "auto-apply" % (row["stem"], cause))
            if cause == causes.UNDETERMINED and floor is not None:
                stops.append(
                    "capture %s: attribution underdetermined on the corpus "
                    "alone — a weighed benchmark capture of this dish would "
                    "settle it" % row["stem"])
            tasks.append({"title": title, "details": details})

    return cycle_file.write(cycle, tasks, stops, cycles_dir)


def next_cycle(cycles_dir=CYCLES_DIR) -> int:
    existing = [int(p.name.split("-")[1]) for p in Path(cycles_dir).glob("cycle-*")
                if p.name.split("-")[1].isdigit()] if Path(cycles_dir).exists() else []
    return max(existing) + 1 if existing else 1


def run(args) -> int:
    root = corpus.ensure_layout(
        Path(args.corpus) if args.corpus else corpus.corpus_root())
    conn = corpus.open_index(root)
    settings = config.load(args.config)
    cycles_dir = Path(args.cycles_dir) if args.cycles_dir else CYCLES_DIR
    cycle = args.cycle or next_cycle(cycles_dir)

    rows, floor = collect(conn, cycle, settings,
                          replay_checkpoint=args.replay_checkpoint)
    path = build_cycle_file(rows, floor, cycle, cycles_dir)

    statuses = {}
    causes_seen = {}
    for row in rows:
        statuses[row["replay_status"]] = statuses.get(row["replay_status"], 0) + 1
        for note in row["notes"]:
            cause = note.get("cause", causes.UNDETERMINED)
            causes_seen[cause] = causes_seen.get(cause, 0) + 1

    print("diagnose cycle=%d captures=%d clusters=%d floor_g=%s"
          % (cycle, len(rows), len({r["cluster_id"] for r in rows}),
             "unmeasured" if floor is None else floor))
    for status in sorted(statuses):
        print("diagnose replay_status=%s n=%d" % (status, statuses[status]))
    for cause in sorted(causes_seen):
        print("diagnose cause=%s n=%d" % (cause, causes_seen[cause]))
    print("diagnose skewed=%d excluded_from_floor=%d"
          % (sum(1 for r in rows if r["replay_version_skew"]),
             sum(1 for r in rows if r["replay_version_skew"])))
    print("diagnose cycle_file=%s" % path)
    conn.close()
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--corpus")
    ap.add_argument("--cycle", type=int, help="cycle number (default: next unused)")
    ap.add_argument("--cycles-dir")
    ap.add_argument("--config")
    ap.add_argument("--replay-checkpoint",
                    help="checkpoint the REPLAYING binary holds; differing from "
                         "a capture's stamps that pair version-skewed")
    return run(ap.parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""One whole cycle, end to end, with everything external stubbed (task 27).

The unit suites each hold one stage still and prod it. This one runs the
stages in the order a real cycle runs them — `field_pull --pull-dir` into the
corpus, `field_diagnose` over what landed, the agent phase's drafts dropped
into the cycle directory, `field_close` judging them — and asserts the joins
between them, which is where a contract breaks without any single stage's
tests noticing.

Three seams are stubbed, and only three, because only three reach outside the
process: `HarnessCLI diagnose` (the Swift replay), `make food-db` (the bake
guard 5 measures across), and `make test` + `make food-db` (guard 6). The
device is replaced by a committed session description; the agent phase by a
committed `drafts.json`, which is literally the file `field_close` reads; and
the loop branch by a throwaway git repository this test creates. Nothing here
may touch the checkout it runs in.

The stub replay is not a lookup table. It scales each capture's predicted
carbohydrate by (current density / source density), reading the overlay file
`field_close` is writing, so an entry that lands genuinely moves the weighed
before/after — guard 5's veto is measured in this rehearsal, not asserted into
existence.

What the cycle is built to demonstrate:

* a fix whose stated evidence and weighed benchmark agree — it commits;
* a fix equally well evidenced by stated values whose weighed benchmark
  contradicts it — demoted at guard 5, because stated values steer and weighed
  values veto (Req 5.4);
* a third fix refused before any guard runs, because the cycle's commit cap is
  spent (Req 5.5);
* a refusal capture that becomes a STOP line rather than a task, and a
  terminal close task after it, which is the cycle-termination contract
  (Decision 15) as an artifact rather than as a claim.
"""

import contextlib
import io
import json
import shutil
import subprocess
from pathlib import Path

import pytest

from candidate_probe import BACKGROUND, CLASS_NAMES
from conftest import grey_png, make_fixture, make_meals_db, make_note, snapshot_of
from field_loop import config, corpus, cycle_file, field_close, field_diagnose, field_pull

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "rehearsal"

# One, so the cap is reachable inside a session small enough to read. Every
# other threshold is the shipped one — a rehearsal against invented floors
# would prove nothing about the loop that runs.
REHEARSAL_COMMIT_CAP = 1


# --------------------------------------------------------------- the session

def _materialise(session, pull: Path) -> None:
    """The committed session description as a pull directory on disk."""
    base = session["base_timestamp_ms"]
    outcomes, benchmarks = [], []

    for attempt in session["attempts"]:
        timestamp_ms = base + attempt["offset_s"] * 1000
        outcome = attempt.get("outcome", "success")
        stem = corpus.stem_for(timestamp_ms, outcome)
        dish = attempt["dish"]
        replayable = attempt.get("replayable", True)

        # A refusal is recorded before segmentation, so its argmax names no
        # food — the absence the cause taxonomy reads as structurally absent.
        classes = (CLASS_NAMES.index(dish),) if replayable else (BACKGROUND,)
        make_fixture(pull / "captures" / ("%s.fixture" % stem), fixture_id=stem,
                     classes=classes, with_probs=not attempt.get("slimmed"))
        if attempt.get("slimmed"):
            (pull / "captures" / ("%s.slimmed" % stem)).write_text("")

        outcome_id = "o-%s" % stem
        row = {"id": outcome_id, "timestamp": timestamp_ms, "outcome": outcome}
        benchmark = attempt.get("benchmark")
        if benchmark:
            row["benchmark_meal_id"] = benchmark["id"]
            benchmarks.append({"id": benchmark["id"], "name": benchmark["name"],
                               "created_at": timestamp_ms,
                               "truth_carbs_g": benchmark["truth_carbs_g"]})
        outcomes.append(row)

        note = attempt.get("note")
        if not note:
            continue
        snapshot = None
        if note.get("displayed_carbs_g") is not None:
            snapshot = snapshot_of((dish, note["displayed_mass_g"],
                                    note["displayed_carbs_g"]))
        make_note(pull / "notes" / ("%s.json" % note["id"]), note_id=note["id"],
                  created_at_ms=timestamp_ms + 2_000, text=note["text"],
                  screen_id=note.get("screen_id", "capture.result"),
                  carbs_g=note.get("stated_carbs_g"),
                  meal={"outcome_id": outcome_id, "timestamp_ms": timestamp_ms},
                  snapshot=snapshot, build_stamp=session["build_stamp"],
                  model_version=session["model_version"])

    for note in session["loose_notes"]:
        make_note(pull / "notes" / ("%s.json" % note["id"]), note_id=note["id"],
                  created_at_ms=base, text=note["text"],
                  screen_id=note["screen_id"], screenshot=note.get("screenshot"),
                  build_stamp=session["build_stamp"],
                  model_version=session["model_version"])
        if note.get("screenshot"):
            (pull / "notes" / note["screenshot"]).write_bytes(grey_png(8, 8))

    make_meals_db(pull / "meals.sqlite", outcomes=outcomes, benchmarks=benchmarks)


def _bake_stub(repo: Path, baked: Path):
    """`make food-db`: the overlay becomes the databases the replay reads.

    Guard 5's before/after only exists because the overlay entry is written
    before the bake and the databases change only when the bake runs. A stub
    that let the replay read the overlay directly would measure the same
    number twice and the veto would never fire.
    """
    overlay_path = repo / "tools" / "food_db" / "loop_overlay.json"
    resources = repo / "MedataCore" / "Sources" / "Foods" / "Resources"

    def bake(repo_argument, settings, **kwargs):
        entries = overlay_path.read_text() if overlay_path.exists() else "[]"
        baked.write_text(entries)
        # The real bake rewrites both databases, and the commit pairs them
        # with the overlay edit that produced them (Req 5.6).
        for name in ("cofid_db.sqlite", "afcd_db.sqlite"):
            (resources / name).write_bytes(b"baked:" + entries.encode())
        return True, "rehearsal bake"

    return bake


def _replay_stub(session, baked: Path):
    """`HarnessCLI diagnose`, standing in for the Swift half.

    Carbohydrate is proportional to density at a fixed recovered volume, so
    scaling each capture's baked figure by the baked-vs-source density ratio
    is enough for a landed fix to move the weighed error for real.
    """
    base = session["base_timestamp_ms"]
    by_stem = {corpus.stem_for(base + a["offset_s"] * 1000,
                               a.get("outcome", "success")): a
               for a in session["attempts"]}

    def replay(fixture_path, checkpoint, replay_checkpoint):
        attempt = by_stem[Path(fixture_path).stem]
        if not attempt.get("replayable", True):
            return {"replay_status": "not_replayable",
                    "replay_failure_reason": "the capture refused before "
                                             "segmentation ran",
                    "replay_version_skew": False}
        dish = attempt["dish"]
        overlay = json.loads(baked.read_text())
        scale = (field_close.prior_value(overlay, dish, "density")
                 / field_close.source_value(dish, "density"))
        total = round(attempt["base_total_carbs_g"] * scale, 4)
        return {"replay_status": "replayed",
                "replay_version_skew": checkpoint != replay_checkpoint,
                "dominant_class": dish,
                "predicted_carbs_per_class": {dish: total},
                "per_class_volumes_cm3": {dish: attempt["volume_cm3"]},
                "predicted_total_carbs_g": total,
                "replay_database_sha256": "rehearsal"}

    return replay


def _throwaway_repo(repo: Path) -> Path:
    """The loop branch, as a repository that is not this checkout."""
    (repo / "tools" / "food_db").mkdir(parents=True)
    (repo / "MedataCore" / "Sources" / "Foods" / "Resources").mkdir(parents=True)
    (repo / "tools" / "food_db" / "loop_overlay.json").write_text("[]\n")
    for name in ("cofid_db.sqlite", "afcd_db.sqlite"):
        (repo / "MedataCore/Sources/Foods/Resources" / name).write_bytes(b"before")
    for argv in (("git", "init", "-q", "-b", "field-loop"),
                 ("git", "config", "user.email", "loop@example.invalid"),
                 ("git", "config", "user.name", "Field Loop Rehearsal"),
                 ("git", "add", "-A"),
                 ("git", "commit", "-qm", "base")):
        subprocess.run(argv, cwd=str(repo), capture_output=True, check=True)
    return repo


def _rehearsal_config(path: Path) -> Path:
    settings = config.load()
    settings["max_commits_per_cycle"] = REHEARSAL_COMMIT_CAP
    # Guard 6 fails closed without one (Decision 20), and the rehearsal stubs
    # the bake it names rather than shipping a calibration artifact.
    settings["calibration_artifact"] = "(stubbed by the loop rehearsal)"
    path.write_text(json.dumps(settings, indent=2, sort_keys=True))
    return path


def _capture(main, argv) -> str:
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        assert main(argv) == 0
    return buffer.getvalue()


# ------------------------------------------------------------------ the cycle

@pytest.fixture(scope="module")
def rehearsal(tmp_path_factory):
    """Run the whole cycle once; every test below reads its artifacts."""
    workspace = tmp_path_factory.mktemp("rehearsal")
    patch = pytest.MonkeyPatch()
    try:
        root = workspace / "medata-corpus"
        patch.setenv(corpus.CORPUS_ENV, str(root))
        corpus.ensure_layout(root)

        session = json.loads((FIXTURES / "session.json").read_text())
        pull = root / "pulls" / "20260827-1"
        _materialise(session, pull)

        repo = _throwaway_repo(workspace / "loop-worktree")
        cycles = workspace / "cycles"
        settings = _rehearsal_config(workspace / "loop_config.json")

        # What the shipped databases hold before this cycle: nothing of the
        # loop's. The bake stub is the only thing that ever moves it.
        baked = workspace / "baked_overlay.json"
        baked.write_text("[]")

        patch.setattr(field_diagnose, "swift_replay", _replay_stub(session, baked))
        patch.setattr(field_close, "bake", _bake_stub(repo, baked))
        patch.setattr(field_close, "build_gates",
                      lambda draft, settings_, **kwargs: (True, "rehearsal stub"))

        common = ["--corpus", str(root)]
        output = {"pull": _capture(field_pull.main,
                                   [*common, "--pull-dir", str(pull)])}
        output["diagnose"] = _capture(
            field_diagnose.main,
            [*common, "--cycle", "1", "--cycles-dir", str(cycles),
             "--config", str(settings)])

        cycle_dir = cycles / "cycle-1"
        shutil.copy(FIXTURES / "drafts.json", cycle_dir / "drafts.json")

        output["close"] = _capture(
            field_close.main,
            [*common, "--cycle", "1", "--cycles-dir", str(cycles),
             "--config", str(settings), "--repo", str(repo),
             "--applied-at", "2026-08-27"])

        index = corpus.open_index(root)
        try:
            yield {
                "output": output, "root": root, "repo": repo,
                "cycle_dir": cycle_dir, "index": index, "session": session,
                "verdict": json.loads((cycle_dir / "verdict.json").read_text()),
                "tasks": (cycle_dir / "tasks.md").read_text(),
                # The rolling ledger lands beside the cycles directory
                # (Decision 23), not inside the cycle.
                "triage": (cycles.parent / "triage.md").read_text(),
                "overlay": json.loads(
                    (repo / "tools/food_db/loop_overlay.json").read_text()),
            }
        finally:
            index.close()
    finally:
        patch.undo()


def _git(repo, *argv) -> str:
    return subprocess.run(["git", *argv], cwd=str(repo), capture_output=True,
                          text=True).stdout


# ---------------------------------------------------------------- ingest (3.3)

def test_the_session_lands_in_the_corpus_whole(rehearsal):
    counts = dict(rehearsal["index"].execute(
        "SELECT 'captures', count(*) FROM captures "
        "UNION ALL SELECT 'notes', count(*) FROM notes "
        "UNION ALL SELECT 'benchmarks', count(*) FROM benchmark_meals").fetchall())
    session = rehearsal["session"]
    assert counts["captures"] == len(session["attempts"])
    assert counts["notes"] == (
        sum(1 for a in session["attempts"] if a.get("note"))
        + len(session["loose_notes"]))
    assert counts["benchmarks"] == sum(
        1 for a in session["attempts"] if a.get("benchmark"))


def test_every_meal_linked_note_finds_its_capture(rehearsal):
    unmatched = rehearsal["index"].execute(
        "SELECT count(*) FROM notes WHERE meal_linked = 1 AND stem IS NULL"
    ).fetchone()[0]
    assert unmatched == 0
    assert "unmatched" not in rehearsal["output"]["pull"]


def test_a_bundle_without_probability_tensors_is_marked_slimmed(rehearsal):
    slimmed = [r[0] for r in rehearsal["index"].execute(
        "SELECT stem FROM captures WHERE slimmed = 1")]
    assert len(slimmed) == 1


def test_the_pull_summary_prints_the_single_copy_acceptance(rehearsal):
    """Req 8.3: device-side pruning is gated on the risk being visible."""
    assert corpus.SINGLE_COPY_ACCEPTANCE in rehearsal["output"]["pull"]


# -------------------------------------------------------------- diagnose (4.x)

def test_every_annotated_capture_is_diagnosed(rehearsal):
    rows = [dict(r) for r in rehearsal["index"].execute(
        "SELECT * FROM diagnoses WHERE cycle = 1")]
    annotated = sum(1 for a in rehearsal["session"]["attempts"] if a.get("note"))
    assert len(rows) == annotated
    assert all(r["replay_version_skew"] == 0 for r in rows)


def test_the_steady_volume_captures_are_attributed_to_density(rehearsal):
    causes_seen = dict(rehearsal["index"].execute(
        "SELECT cause, count(*) FROM diagnoses WHERE cycle = 1 GROUP BY cause"))
    assert causes_seen["wrong_density_conversion"] == 12
    assert causes_seen["refusal_should_have_succeeded"] == 1


def test_the_attribution_floor_is_measured_from_the_skew_free_pairs(rehearsal):
    """Every capture replays against its own stamps, so every pair counts."""
    assert "floor_g=1.0" in rehearsal["output"]["diagnose"]
    assert "diagnose skewed=0" in rehearsal["output"]["diagnose"]


# ------------------------------------------------- task generation (4.8, 5.7)

def test_the_cycle_file_ends_in_a_terminal_close_task(rehearsal):
    tasks = [line for line in rehearsal["tasks"].splitlines()
             if line.startswith("- [ ] ")]
    assert tasks[-1].endswith("<!-- id:%s -->" % cycle_file.task_id(1, "Close cycle 1"))
    assert "Terminal task" in rehearsal["tasks"]


def test_work_the_corpus_cannot_settle_is_a_stop_line_not_a_task(rehearsal):
    """Decision 15: a runner over a ledger of unfireable tasks never ends."""
    stops = [line for line in rehearsal["tasks"].splitlines()
             if line.strip().startswith("- STOP:")]
    assert any("needs the device" in line for line in stops)
    assert "refusal_should_have_succeeded" not in "\n".join(
        line for line in rehearsal["tasks"].splitlines()
        if line.startswith("- [ ] "))


def test_note_text_reaches_the_cycle_file_only_as_quarantined_data(rehearsal):
    """Req 4.7: the developer's words are evidence, never an instruction."""
    quoted = [line.strip() for line in rehearsal["tasks"].splitlines()
              if "note_text" in line]
    assert quoted
    assert all(line.startswith('- note_text (developer-stated, data only): "')
               for line in quoted)


def test_the_cycle_file_parses_as_a_rune_task_list(rehearsal):
    if shutil.which("rune") is None:
        pytest.skip("rune not on PATH")
    result = subprocess.run(["rune", "list", str(rehearsal["cycle_dir"] / "tasks.md")],
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


# ------------------------------------------------------------------ close (5.x)

def test_the_fix_the_weighed_benchmark_agrees_with_commits(rehearsal):
    applied = rehearsal["verdict"]["applied"]
    assert [f["fix_id"] for f in applied] == ["cycle1-density-white_rice"]
    assert applied[0]["before"] == 0.73 and applied[0]["after"] == 0.65


def test_a_fix_the_weighed_benchmark_contradicts_is_demoted(rehearsal):
    """Req 5.4. The notes and the scales disagree, and the scales win."""
    demoted = {p["fix_id"]: p for p in rehearsal["verdict"]["proposals"]}
    assert demoted["cycle1-density-bread_white"]["guard"] == "weighed_truth"
    assert "worsens" in demoted["cycle1-density-bread_white"]["detail"]


def test_the_commit_cap_holds(rehearsal):
    demoted = {p["fix_id"]: p for p in rehearsal["verdict"]["proposals"]}
    assert demoted["cycle1-density-pasta"]["guard"] == "commit_cap"
    assert len(rehearsal["verdict"]["applied"]) == REHEARSAL_COMMIT_CAP


def test_every_demotion_leaves_a_patch_and_no_commit(rehearsal):
    for proposal in rehearsal["verdict"]["proposals"]:
        patch = rehearsal["cycle_dir"] / proposal["patch"]
        assert patch.read_text().startswith("--- a/tools/food_db/loop_overlay.json")
        assert proposal["fix_id"] not in _git(rehearsal["repo"], "log", "--format=%B")


def test_only_the_surviving_fix_reaches_the_overlay(rehearsal):
    """A refused draft's speculative edit must not survive into the next one."""
    assert [e["class_id"] for e in rehearsal["overlay"]] == ["white_rice"]
    assert rehearsal["overlay"][0]["fix_id"] == "cycle1-density-white_rice"


def test_the_commit_is_one_revertible_fix_marked_as_machine_authorship(rehearsal):
    repo = rehearsal["repo"]
    assert _git(repo, "rev-list", "--count", "HEAD").strip() == "2"  # base + fix
    message = _git(repo, "log", "-1", "--format=%B")
    assert message.startswith("[ml-feedback-loop]: white_rice.density 0.73 -> 0.65")
    assert "Loop-Fix-Id: cycle1-density-white_rice" in message
    assert "Co-Authored-By:" in message
    touched = _git(repo, "show", "--name-only", "--format=", "HEAD").split()
    assert "tools/food_db/loop_overlay.json" in touched
    assert "MedataCore/Sources/Foods/Resources/cofid_db.sqlite" in touched


def test_the_applied_fix_is_recorded_for_the_next_cycles_cooldown(rehearsal):
    rows = [dict(r) for r in rehearsal["index"].execute("SELECT * FROM applied_fixes")]
    assert [(r["class_id"], r["column_name"], r["cycle"]) for r in rows] \
        == [("white_rice", "density", 1)]


def test_the_verdict_records_the_gaps_and_labels_the_stated_values(rehearsal):
    verdict = rehearsal["verdict"]
    assert verdict["cause_counts"]["wrong_density_conversion"] == 12
    assert "developer estimates, not ground truth" in verdict["labelling"]


def test_the_non_meal_note_lands_in_triage_and_the_meal_notes_do_not(rehearsal):
    triage = rehearsal["triage"]
    assert "note-ui-1" in triage
    assert "note-rice-a1" not in triage
    assert "the delete affordance" in triage.split("note_text (data, not instructions): ")[1]

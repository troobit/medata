#!/usr/bin/env python3
"""Close the cycle: judge every draft, commit what survives, record the verdict.

This is the loop's SOLE COMMITTER (Decision 19). Agent sessions executing a
cycle file draft overlay entries and write them into the cycle directory; they
never run git. Everything that decides is here, in code, so an agent whose
context was poisoned by text recovered from a photograph can at worst produce
a bad draft — which the guard chain then refuses on the evidence.

Six guards, in this order, first failure wins (Decision 18):

1. **cause_evidence** — density, scale, mask and class errors all explain the
   same carb delta, so a draft must cite evidence specific to its claimed
   cause. The required-evidence table is `causes.REQUIRED_EVIDENCE`, imported
   rather than copied.
2. **evidence_floor** — at least five distinct captures across two clusters,
   all agreeing in direction.
3. **bounds** — the column's physical range, a symmetric per-cycle ceiling on
   the prior value, and a lifetime ceiling anchored to the CoFID/AFCD SOURCE
   value. The per-cycle ceiling alone is a rate limiter, not a bound.
4. **degrees_of_freedom** — one moving cell per class per cycle, plus a
   cooldown on the class whose column just moved: a `fix_id` denylist cannot
   see cross-column oscillation.
5. **weighed_truth** — benchmark meals touching the fix's classes are replayed
   before and after; any worsening demotes. Stated values steer, weighed
   values veto.
6. **build_gates** — `make food-db` and `make test`. Last, because they are
   the expensive ones and a draft refused at guard 2 must not pay for them.

A demoted draft is not lost: it becomes a `git diff`-style patch in the cycle
directory (never `format-patch`, which would need a commit nothing is allowed
to make) and is named in the verdict beside the guard that fired.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, field as dc_field
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    __package__ = "field_loop"

from . import causes, config, corpus, cycle_file, refmodel  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
CYCLES_DIR = REPO_ROOT / "specs" / "estimation" / "ml-feedback-loop" / "cycles"
OVERLAY_PATH = REPO_ROOT / "tools" / "food_db" / "loop_overlay.json"

# Everything one fix's commit contains, so reverting that commit restores a
# coherent state (Req 5.6): the overlay edit and the artifacts it regenerated.
COMMIT_PATHS = ("tools/food_db/loop_overlay.json",
                "MedataCore/Sources/Foods/Resources/cofid_db.sqlite",
                "MedataCore/Sources/Foods/Resources/afcd_db.sqlite")

COMMIT_SUBJECT_PREFIX = "[ml-feedback-loop]: "

# Req 5.5. Neither is ever a commit target, whatever the configuration says.
FORBIDDEN_BRANCHES = ("research", "main")

GUARDS = ("cause_evidence", "evidence_floor", "bounds", "degrees_of_freedom",
          "weighed_truth", "build_gates")

# Guard 5's "the after could not be measured" value. Infinity rather than None
# so it compares as a worsening wherever the veto looks at it: a fix whose
# effect on weighed truth is unknown is exactly what the veto exists to stop.
UNMEASURABLE = float("inf")

# Causes the overlay can actually address. Class selection and palette gaps
# need a model or a class-set change, which are outside the overlay by
# construction — a draft claiming one of them is a proposal by definition.
OVERLAY_CAUSES = (causes.WRONG_DENSITY, causes.WRONG_SCALE)


@dataclass
class GuardResult:
    ok: bool
    guard: str | None = None
    detail: str = ""


@dataclass
class Draft:
    """One candidate overlay edit, as an agent phase produced it."""

    fix_id: str
    class_id: str
    column: str
    value: float
    cause: str
    basis: dict = dc_field(default_factory=dict)
    region: str | None = None
    vessel: str | None = None
    expected_effect: str = ""

    @classmethod
    def from_dict(cls, payload: dict) -> "Draft":
        missing = [k for k in ("fix_id", "class_id", "column", "value", "cause")
                   if k not in payload]
        if missing:
            raise SystemExit("draft is missing %s" % ", ".join(missing))
        return cls(fix_id=payload["fix_id"], class_id=payload["class_id"],
                   column=payload["column"], value=float(payload["value"]),
                   cause=payload["cause"], basis=payload.get("basis") or {},
                   region=payload.get("region"), vessel=payload.get("vessel"),
                   expected_effect=payload.get("expected_effect", ""))

    @property
    def cell(self) -> tuple:
        return (self.class_id, self.column, self.region, self.vessel)

    def as_overlay_entry(self, applied_at: str) -> dict:
        entry = {"class_id": self.class_id, "column": self.column,
                 "value": self.value, "basis": self.basis,
                 "fix_id": self.fix_id, "applied_at": applied_at}
        if self.region:
            entry["region"] = self.region
        if self.vessel:
            entry["vessel"] = self.vessel
        return entry


def load_drafts(cycle_dir) -> list:
    """`drafts.json` in the cycle directory: what the agent phase produced."""
    path = Path(cycle_dir) / "drafts.json"
    if not path.exists():
        return []
    payload = json.loads(path.read_text())
    if not isinstance(payload, list):
        raise SystemExit("%s must be a JSON list of drafts" % path)
    return [Draft.from_dict(item) for item in payload]


# ------------------------------------------------------------ value lookups

def _generate():
    """The generator module, imported lazily — it is a big stdlib-only file."""
    sys.path.insert(0, str(REPO_ROOT / "tools"))
    from food_db import generate

    return generate


def source_value(class_id: str, column: str, region=None, vessel=None):
    """The ORIGINAL CoFID/AFCD value, which the lifetime bound is anchored to.

    Read from the generator's in-memory tables, never from a baked database:
    a database already carries whatever the overlay put there, so anchoring to
    it would let the bound drift along with the value it is bounding.
    """
    generate = _generate()
    if column in generate._FOODS_COLUMN_INDEX:
        row = next((r for r in generate.FOOD_DATA if r[0] == class_id), None)
        return None if row is None else row[generate._FOODS_COLUMN_INDEX[column]]
    if column == "solid_servings.grams_per_unit":
        row = next((r for r in generate.SOLID_SERVINGS if r[0] == class_id), None)
        return None if row is None else row[generate._SOLID_GRAMS_PER_UNIT]
    if column == "liquid_servings.serving_ml":
        row = next((r for r in generate.LIQUID_SERVINGS
                    if (r[0], r[1], r[2]) == (class_id, region, vessel)), None)
        return None if row is None else row[generate._LIQUID_SERVING_ML]
    return None


def prior_value(overlay: list, class_id: str, column: str, region=None,
                vessel=None):
    """The value currently in effect: a landed overlay value, else the source."""
    for entry in overlay or []:
        if (entry.get("class_id"), entry.get("column"), entry.get("region"),
                entry.get("vessel")) == (class_id, column, region, vessel):
            return entry["value"]
    return source_value(class_id, column, region, vessel)


def required_evidence(cause: str) -> tuple:
    """The taxonomy's own table. Guard 1 reads it; it does not restate it."""
    return causes.REQUIRED_EVIDENCE.get(cause, ())


# -------------------------------------------------------------------- guards

def denylist(settings: dict, cycles_dir) -> set:
    """Configured refusals plus every fix a prior verdict called regressive.

    Req 5.7 is about what a PRIOR RUN found, so the verdicts are the record —
    the configured list is for refusals a human wants to outlive them.
    """
    out = set(config.get(settings, "denylist") or [])
    directory = Path(cycles_dir)
    if directory.exists():
        for verdict in sorted(directory.glob("cycle-*/verdict.json")):
            try:
                document = json.loads(verdict.read_text())
            except ValueError:
                continue
            out.update(document.get("regressive_fix_ids") or [])
    return out


def guard_cause_evidence(draft: Draft, diagnoses: list) -> GuardResult:
    if draft.cause not in OVERLAY_CAUSES:
        return GuardResult(
            False, "cause_evidence",
            "cause %s cannot be fixed in the overlay — the palette, the class "
            "set and the model are outside it by construction (Req 5.1)"
            % draft.cause)

    supporting = [d for d in diagnoses if d.get("cause") == draft.cause]
    if not supporting:
        return GuardResult(
            False, "cause_evidence",
            "no diagnosis in the corpus classified a cited capture as %s; "
            "density, scale, mask and class errors all explain the same carb "
            "delta, so evidence for another cause is not evidence for this one"
            % draft.cause)

    needed = required_evidence(draft.cause)
    for name in needed:
        carrying = [d for d in supporting
                    if json.loads(d.get("evidence_json") or "{}").get(name)
                    is not None]
        if not carrying:
            return GuardResult(
                False, "cause_evidence",
                "cause %s requires evidence field '%s', which no cited "
                "diagnosis carries" % (draft.cause, name))
    return GuardResult(True)


def guard_evidence_floor(draft: Draft, diagnoses: list,
                         settings: dict) -> GuardResult:
    min_captures = config.get(settings, "evidence_min_captures")
    min_clusters = config.get(settings, "evidence_min_clusters")

    supporting = [d for d in diagnoses if d.get("cause") == draft.cause]
    by_stem = {d["stem"]: d for d in supporting}
    if len(by_stem) < min_captures:
        return GuardResult(
            False, "evidence_floor",
            "%d distinct captures support this fix; the floor is %d"
            % (len(by_stem), min_captures))

    clusters = {d.get("cluster_id") for d in by_stem.values()}
    if len(clusters) < min_clusters:
        return GuardResult(
            False, "evidence_floor",
            "%d cluster(s) — the floor is %d; captures from one cluster are "
            "one scene photographed repeatedly, not independent evidence"
            % (len(clusters), min_clusters))

    directions = set()
    for row in by_stem.values():
        gap = json.loads(row.get("evidence_json") or "{}").get("gap_g")
        if gap is not None:
            directions.add(gap > 0)
    if len(directions) > 1:
        return GuardResult(
            False, "evidence_floor",
            "cited captures disagree in direction — some over-, some "
            "under-estimated; a value change cannot satisfy both")
    return GuardResult(True)


def guard_bounds(draft: Draft, prior, source, settings: dict) -> GuardResult:
    generate = _generate()
    span = generate.OVERLAY_COLUMNS.get(draft.column)
    if span is None:
        return GuardResult(
            False, "bounds",
            "column %s is not on the overlay allowlist" % draft.column)
    low, high = span
    if not low <= draft.value <= high:
        return GuardResult(
            False, "bounds",
            "%s = %s is outside the declared physical bounds %s-%s for %s"
            % (draft.class_id, draft.value, low, high, draft.column))

    per_cycle = config.get(settings, "per_cycle_drift_ceiling")
    if prior:
        move = abs(draft.value - prior) / abs(prior)
        if move > per_cycle:
            return GuardResult(
                False, "bounds",
                "per_cycle drift %.4f exceeds the ceiling %.4f (%s -> %s)"
                % (move, per_cycle, prior, draft.value))

    lifetime = config.get(settings, "lifetime_drift_ceiling")
    if source:
        total = abs(draft.value - source) / abs(source)
        if total > lifetime:
            return GuardResult(
                False, "bounds",
                "lifetime drift %.4f from the source value %s exceeds the "
                "ceiling %.4f — the per-cycle ceiling only limits the rate"
                % (total, source, lifetime))
    return GuardResult(True)


def guard_degrees_of_freedom(draft: Draft, cycle: int, applied_this_cycle: list,
                             history: list, settings: dict) -> GuardResult:
    for other in applied_this_cycle:
        if other.class_id == draft.class_id:
            return GuardResult(
                False, "degrees_of_freedom",
                "%s already moved this cycle (%s); one degree of freedom per "
                "class per cycle keeps a change attributable"
                % (draft.class_id, other.column))

    cooldown = config.get(settings, "column_cooldown_cycles")
    for row in history:
        if row.get("class_id") != draft.class_id:
            continue
        if row.get("column") == draft.column:
            continue
        age = cycle - int(row.get("cycle", 0))
        if 0 <= age <= cooldown:
            return GuardResult(
                False, "degrees_of_freedom",
                "column cooldown: %s.%s moved in cycle %s, so a different "
                "column on the same class waits %d cycle(s) — fix_id "
                "denylisting cannot see cross-column oscillation"
                % (draft.class_id, row.get("column"), row.get("cycle"),
                   cooldown))
    return GuardResult(True)


def guard_weighed_truth(draft: Draft, weighed) -> GuardResult:
    """Replay the weighed benchmarks this fix touches, before and after.

    `weighed(draft)` returns `(before_error_g, after_error_g)`, or None when
    the fix's classes have no weighed coverage. None passes: this is a veto on
    evidence, not a gate demanding evidence — requiring benchmark coverage for
    every class would stop the loop everywhere the benchmark set is thin.
    """
    measured = weighed(draft)
    if measured is None:
        return GuardResult(True, detail="no weighed coverage for these classes")
    before, after = measured
    if after == UNMEASURABLE:
        return GuardResult(
            False, "weighed_truth",
            "weighed carbohydrate error was %s before the fix and could not be "
            "measured after it; the veto lets nothing past it could not check"
            % before)
    if after > before:
        return GuardResult(
            False, "weighed_truth",
            "weighed carbohydrate error worsens %s -> %s; stated values steer, "
            "weighed values veto" % (before, after))
    return GuardResult(True, detail="weighed error %s -> %s" % (before, after))


def build_gates(draft: Draft, settings: dict, runner=subprocess.run,
                repo=REPO_ROOT) -> tuple:
    """`make food-db` then `make test`, both totals. Returns (ok, detail).

    With no calibration artifact configured the bake refuses to run at all
    (Decision 20), so the gate fails and the fix demotes — the safe direction:
    a stalled cycle with proposals beats a stream of lineage-stripping commits.
    """
    artifact = config.get(settings, "calibration_artifact")
    if not artifact:
        return False, (
            "loop_config.json has no calibration_artifact, so `make food-db` "
            "would abort rather than re-bake databases that carry calibration "
            "lineage (Decision 20)")

    food_db = runner(["make", "food-db", "CALIBRATION=%s" % artifact],
                     cwd=str(repo), capture_output=True, text=True)
    if food_db.returncode != 0:
        return False, "make food-db failed: %s" % (food_db.stderr or "")[-300:].strip()

    tests = runner(["make", "test"], cwd=str(repo), capture_output=True, text=True)
    if tests.returncode != 0:
        return False, "make test failed: %s" % (tests.stderr or "")[-300:].strip()
    return True, "make food-db and make test green"


def guard_build_gates(draft: Draft, gates) -> GuardResult:
    ok, detail = gates(draft)
    return GuardResult(ok, None if ok else "build_gates", detail)


def evaluate(draft: Draft, *, cycle: int, settings: dict, diagnoses: list,
             prior_value, source_value, applied_this_cycle: list,
             history: list, weighed, gates) -> GuardResult:
    """Run the chain in order and report the FIRST refusal.

    Order is the contract: a bounds failure reported where an evidence failure
    fired would send the next cycle looking for the wrong problem.
    """
    if draft.fix_id in set(config.get(settings, "denylist") or []):
        return GuardResult(
            False, "denylist",
            "fix id %s is denylisted — a prior verdict flagged it regressive "
            "and the loop never re-applies one (Req 5.7)" % draft.fix_id)

    checks = (
        lambda: guard_cause_evidence(draft, diagnoses),
        lambda: guard_evidence_floor(draft, diagnoses, settings),
        lambda: guard_bounds(draft, prior_value, source_value, settings),
        lambda: guard_degrees_of_freedom(draft, cycle, applied_this_cycle,
                                         history, settings),
        lambda: guard_weighed_truth(draft, weighed),
        lambda: guard_build_gates(draft, gates),
    )
    detail = ""
    for check in checks:
        result = check()
        if not result.ok:
            return result
        detail = result.detail or detail
    return GuardResult(True, None, detail)


# ------------------------------------------------------------------- overlay

def append_overlay(path, draft: Draft, applied_at: str) -> list:
    """Land one entry, replacing any prior entry for the same cell.

    The bake refuses an overlay that targets one cell twice, so replacement is
    the only correct shape here — appending a second entry would abort the
    very bake this fix's commit has to contain.
    """
    path = Path(path)
    overlay = json.loads(path.read_text()) if path.exists() else []
    entry = draft.as_overlay_entry(applied_at)
    key = (entry["class_id"], entry["column"], entry.get("region"),
           entry.get("vessel"))
    kept = [e for e in overlay
            if (e.get("class_id"), e.get("column"), e.get("region"),
                e.get("vessel")) != key]
    kept.append(entry)
    path.write_text(json.dumps(kept, indent=2, sort_keys=True) + "\n")
    return kept


# ---------------------------------------------------------------- git commits

class Committer:
    """Every git operation the loop is allowed to make, and nothing else."""

    def __init__(self, repo, settings: dict, runner=subprocess.run):
        self.repo = Path(repo)
        self.settings = settings
        self.runner = runner
        self.made = 0

    def _git(self, *argv, check=True):
        result = self.runner(["git", *argv], cwd=str(self.repo),
                             capture_output=True, text=True)
        if check and result.returncode != 0:
            raise SystemExit("git %s failed: %s"
                             % (" ".join(argv), (result.stderr or "").strip()))
        return result

    def branch(self) -> str:
        return self._git("rev-parse", "--abbrev-ref", "HEAD").stdout.strip()

    def require_clean(self) -> None:
        """Refuse a dirty tree and refuse the shared branches (Req 5.5, 5.7).

        A dirty tree would let the loop's commit carry work it did not author,
        which breaks the one-commit-is-one-revertible-fix contract (Req 5.6).
        """
        branch = self.branch()
        if branch in FORBIDDEN_BRANCHES:
            raise SystemExit(
                "refusing to run on '%s': the loop commits only to its own "
                "branch (Req 5.5). Run it in a dedicated worktree — "
                "`make worktree name=field-loop branch=%s`"
                % (branch, config.get(self.settings, "loop_branch")))
        status = self._git("status", "--porcelain").stdout.strip()
        if status:
            raise SystemExit(
                "refusing to run on a dirty tree in %s — an auto-commit would "
                "carry work the loop did not author:\n%s"
                % (self.repo, status))

    def restore(self, path) -> None:
        """Put one tracked file back as HEAD has it.

        A refused draft must leave nothing behind: the overlay edit was written
        speculatively so guards 5 and 6 had something to measure, and it is not
        allowed to survive the refusal into the next draft's `prior_value`.
        """
        self._git("checkout", "--", str(Path(path)))

    def may_commit(self) -> bool:
        return self.made < config.get(self.settings, "max_commits_per_cycle")

    def commit(self, draft: Draft, before, after) -> str:
        if not self.may_commit():
            raise SystemExit("commit cap reached")
        for path in COMMIT_PATHS:
            if (self.repo / path).exists():
                self._git("add", "--", path)
        self._git("commit", "-q", "-m", self.message(draft, before, after))
        self.made += 1
        return self._git("rev-parse", "HEAD").stdout.strip()

    def message(self, draft: Draft, before, after) -> str:
        cell = "%s.%s" % (draft.class_id, draft.column)
        if draft.region or draft.vessel:
            cell += " (%s/%s)" % (draft.region, draft.vessel)
        basis = draft.basis or {}
        lines = [
            "%s%s %s -> %s (%s)" % (COMMIT_SUBJECT_PREFIX, cell, before, after,
                                    draft.cause),
            "",
            "| cell | before | after |",
            "| --- | --- | --- |",
            "| %s | %s | %s |" % (cell, before, after),
            "",
            "Notes: %s" % ", ".join(basis.get("notes") or ["(none cited)"]),
            "Captures: %s" % ", ".join(basis.get("captures") or ["(none cited)"]),
        ]
        if basis.get("rationale"):
            lines += ["", "Rationale (developer-stated evidence, machine-drafted): "
                          + cycle_file.quarantine(basis["rationale"])]
        lines += [
            "",
            "Co-Authored-By: %s" % config.get(self.settings, "commit_coauthor"),
            "Loop-Fix-Id: %s" % draft.fix_id,
        ]
        return "\n".join(lines)


# ----------------------------------------------------------------- proposals

def write_proposal(cycle_dir, draft: Draft, result: GuardResult, before,
                   after) -> Path:
    """The refused edit as a unified diff, and the guard that refused it.

    Deliberately not `git format-patch`: that shape presupposes a commit, and
    a demoted fix is precisely the thing no commit may exist for.
    """
    directory = Path(cycle_dir) / "proposals"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / ("%s.patch" % draft.fix_id)
    entry = json.dumps(draft.as_overlay_entry("(proposed)"), indent=2,
                       sort_keys=True)
    body = [
        "--- a/tools/food_db/loop_overlay.json",
        "+++ b/tools/food_db/loop_overlay.json",
        "@@ overlay entry proposed by cycle draft %s @@" % draft.fix_id,
    ]
    body += ["+%s" % line for line in entry.splitlines()]
    body += [
        "",
        "# demoted at guard: %s" % result.guard,
        "# reason: %s" % result.detail,
        "# would move %s.%s from %s to %s" % (draft.class_id, draft.column,
                                              before, after),
        "# apply by hand after review; the loop will not re-attempt it.",
    ]
    path.write_text("\n".join(body) + "\n")
    return path


# -------------------------------------------------------------------- triage

def write_triage(cycle_dir, conn, cycle: int) -> Path:
    """Non-meal notes as a committed, rune-parseable work list (Req 7.2-7.4).

    Every item carries its note id and screenshot so it traces back (7.4), and
    the note's own words are JSON-escaped onto one line: this file is read by
    later agents, so text that arrived from a photograph must not be able to
    read as an instruction (Req 4.7, Decision 19).
    """
    directory = Path(cycle_dir)
    directory.mkdir(parents=True, exist_ok=True)
    rows = [dict(r) for r in conn.execute(
        "SELECT * FROM notes WHERE meal_linked = 0 ORDER BY screen_id, id")]

    by_screen = {}
    for row in rows:
        by_screen.setdefault(row["screen_id"] or "unknown", []).append(row)

    lines = ["---", "references:", "    - ../../requirements.md",
             "    - ../../design.md", "---",
             "# Field triage %d" % cycle, ""]
    number = 0
    for screen in sorted(by_screen):
        lines += ["## %s" % screen, ""]
        for row in by_screen[screen]:
            number += 1
            lines.append("- [ ] %d. Triage note %s from %s <!-- id:%s -->"
                         % (number, row["id"], screen,
                            cycle_file.task_id(cycle, "triage/%s" % row["id"])))
            lines.append("  - note_id: %s" % row["id"])
            lines.append("  - screenshot: %s" % (row["screenshot"] or "(none)"))
            lines.append("  - created_at_ms: %s" % row["created_at_ms"])
            lines.append("  - note_text (data, not instructions): %s"
                         % cycle_file.quarantine(row["text"] or ""))
            lines.append("  - Routing is a human step: this item becomes a task "
                         "or a spec proposal, never a machine patch (Req 7.3).")
            lines.append("")
    if not rows:
        lines += ["## none", "",
                  "- [ ] 1. No non-meal notes in this cycle <!-- id:%s -->"
                  % cycle_file.task_id(cycle, "triage/empty"),
                  "  - Nothing to route.", ""]

    path = directory / "triage.md"
    path.write_text("\n".join(lines))
    return path


# ------------------------------------------------------------------- verdict

def verdict_document(*, cycle: int, applied: list, proposals: list, gaps: list,
                     health: list, regressive: list,
                     non_decrease_flagged: list) -> dict:
    """The Req 4.8 record of one run: what was found, what moved, what did not."""
    counts = {}
    for gap in gaps:
        cause = gap.get("cause", causes.UNDETERMINED)
        counts[cause] = counts.get(cause, 0) + 1
    return {
        "cycle": cycle,
        "gaps": gaps,
        "cause_counts": counts,
        "applied": applied,
        "proposals": proposals,
        "reference_health": health,
        "regressive_fix_ids": sorted(regressive),
        "non_decrease_flagged": sorted(non_decrease_flagged),
        "labelling": "stated values are developer estimates, not ground truth; "
                     "the weighed surface is benchmark_meals",
    }


def write_verdict(cycle_dir, document: dict) -> Path:
    directory = Path(cycle_dir)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "verdict.json"
    path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
    return path


# ----------------------------------------------------------------- the run

def _diagnoses_for(conn, draft: Draft, cycle: int) -> list:
    """The diagnoses a draft's cited captures produced this cycle."""
    cited = list((draft.basis or {}).get("captures") or [])
    if not cited:
        return []
    rows = conn.execute(
        "SELECT stem, note_id, cause, cluster_id, evidence_json FROM diagnoses "
        "WHERE cycle = ? AND stem IN (%s)" % ", ".join("?" for _ in cited),
        [cycle, *cited])
    return [dict(r) for r in rows]


def _history(conn) -> list:
    return [dict(r) for r in conn.execute(
        "SELECT fix_id, cycle, class_id, column_name AS column FROM applied_fixes")]


def _record_applied(conn, draft: Draft, cycle: int, before, after, sha) -> None:
    conn.execute(
        "INSERT OR REPLACE INTO applied_fixes (fix_id, cycle, class_id, "
        "column_name, prior_value, value, commit_sha) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (draft.fix_id, cycle, draft.class_id, draft.column, before, after, sha))
    conn.commit()


def benchmark_rows(conn, class_id: str) -> list:
    """Weighed benchmark captures whose classes this fix touches.

    The join is outcome -> benchmark meal -> capture, and it is restricted to
    captures that actually priced the class being moved: replaying benchmarks
    the fix cannot affect would dilute the veto with noise until it never
    fires.
    """
    rows = conn.execute(
        "SELECT c.stem, c.detected_classes, c.model_version, b.truth_carbs_g "
        "FROM outcomes o "
        "JOIN benchmark_meals b ON b.id = o.benchmark_meal_id "
        "JOIN captures c ON c.timestamp_ms = o.timestamp_ms "
        "WHERE o.benchmark_meal_id IS NOT NULL ORDER BY c.stem")
    return [dict(r) for r in rows
            if class_id in (r["detected_classes"] or "").split(",")]


def weighed_error(root, rows, replay) -> float | None:
    """Mean absolute carbohydrate error against the WEIGHED figure.

    None when nothing replayed: an unmeasurable "after" must not be reported
    as a perfect one.
    """
    from . import field_diagnose

    errors = []
    for row in rows:
        path = Path(root) / "captures" / ("%s.fixture" % row["stem"])
        if not path.exists():
            continue
        checkpoint = field_diagnose.bare_checkpoint(row.get("model_version"))
        record = replay(path, checkpoint, checkpoint)
        predicted = record.get("predicted_total_carbs_g")
        if predicted is None:
            continue
        errors.append(abs(predicted - row["truth_carbs_g"]))
    return sum(errors) / len(errors) if errors else None


def bake(repo, settings, runner=subprocess.run) -> tuple:
    """`make food-db` alone — the regeneration guard 5 measures across."""
    artifact = config.get(settings, "calibration_artifact")
    if not artifact:
        return False, "no calibration_artifact configured (Decision 20)"
    result = runner(["make", "food-db", "CALIBRATION=%s" % artifact],
                    cwd=str(repo), capture_output=True, text=True)
    if result.returncode != 0:
        return False, (result.stderr or "")[-300:].strip()
    return True, ""


def weighed_replayer(conn, root, settings, repo, replay=None, baker=None):
    """Guard 5's measurement: weighed error with and without the overlay entry.

    The entry is already written when this runs (guards 1-4 passed), so the
    committed databases still hold the PRE-fix values until `baker` regenerates
    them — which is what makes a genuine before/after possible without a second
    checkout.
    """
    from . import field_diagnose

    # Both seams are resolved at call time, not as default arguments: `run()`
    # builds this replayer itself, so a def-time default would put the Swift
    # harness and `make food-db` beyond the reach of the CLI entry point the
    # loop-rehearsal test drives.
    replay = replay or field_diagnose.swift_replay
    baker = baker or bake

    def measure(draft: Draft):
        rows = benchmark_rows(conn, draft.class_id)
        if not rows:
            return None
        before = weighed_error(root, rows, replay)
        if before is None:
            return None
        ok, _detail = baker(repo, settings)
        if not ok:
            # The entry is in place and the bake refuses it, so there is no
            # "after" to compare. Unmeasurable is treated as worsening: the
            # veto's job is to let nothing through it could not check.
            return before, UNMEASURABLE
        after = weighed_error(root, rows, replay)
        return (before, UNMEASURABLE) if after is None else (before, after)

    return measure


def run(args) -> int:
    settings = config.load(args.config)
    cycles_dir = Path(args.cycles_dir) if args.cycles_dir else CYCLES_DIR
    cycle = args.cycle
    cycle_dir = cycles_dir / ("cycle-%d" % cycle)
    if not cycle_dir.exists():
        raise SystemExit("%s does not exist — run `make field-diagnose` first"
                         % cycle_dir)

    root = Path(args.corpus) if args.corpus else corpus.corpus_root()
    conn = corpus.open_index(root)
    settings["denylist"] = sorted(denylist(settings, cycles_dir))

    repo = Path(args.repo) if args.repo else REPO_ROOT
    committer = Committer(repo, settings)
    committer.require_clean()

    overlay_path = repo / "tools" / "food_db" / "loop_overlay.json"
    weighed = weighed_replayer(conn, root, settings, repo)
    history = _history(conn)
    applied, proposals, applied_drafts = [], [], []

    for draft in load_drafts(cycle_dir):
        overlay = json.loads(overlay_path.read_text()) if overlay_path.exists() else []
        before = prior_value(overlay, draft.class_id, draft.column,
                             draft.region, draft.vessel)
        source = source_value(draft.class_id, draft.column, draft.region,
                              draft.vessel)
        if not committer.may_commit():
            result = GuardResult(False, "commit_cap",
                                 "cycle commit cap %d reached"
                                 % config.get(settings, "max_commits_per_cycle"))
        else:
            append_overlay(overlay_path, draft, args.applied_at)
            result = evaluate(
                draft, cycle=cycle, settings=settings,
                diagnoses=_diagnoses_for(conn, draft, cycle),
                prior_value=before, source_value=source,
                applied_this_cycle=applied_drafts, history=history,
                weighed=weighed,
                gates=lambda d: build_gates(d, settings, repo=repo))

        if not result.ok:
            # Nothing partial survives a refusal: the overlay goes back to what
            # it was before this draft touched it, and the draft leaves a patch.
            committer.restore(overlay_path.relative_to(repo))
            proposals.append({
                "fix_id": draft.fix_id, "guard": result.guard,
                "detail": result.detail,
                "patch": str(write_proposal(cycle_dir, draft, result, before,
                                            draft.value).relative_to(cycle_dir)),
            })
            continue

        sha = committer.commit(draft, before, draft.value)
        _record_applied(conn, draft, cycle, before, draft.value, sha)
        applied_drafts.append(draft)
        applied.append({"fix_id": draft.fix_id, "class_id": draft.class_id,
                        "column": draft.column, "before": before,
                        "after": draft.value, "commit": sha,
                        "expected_effect": draft.expected_effect
                        or result.detail})

    health = []
    if args.probe_image:
        adapters = refmodel.enabled_adapters(refmodel.load_config(root=root))
        health = refmodel.health_probe(adapters, args.probe_image)

    document = verdict_document(
        cycle=cycle,
        applied=applied, proposals=proposals,
        gaps=[dict(r) for r in conn.execute(
            "SELECT stem, note_id, cause, replay_status FROM diagnoses "
            "WHERE cycle = ? ORDER BY stem", (cycle,))],
        health=health, regressive=args.regressive or [],
        non_decrease_flagged=args.flagged or [])
    verdict = write_verdict(cycle_dir, document)
    triage = write_triage(cycle_dir, conn, cycle)

    print("close cycle=%d applied=%d proposals=%d" % (cycle, len(applied),
                                                      len(proposals)))
    for item in proposals:
        print("close demoted fix_id=%s guard=%s" % (item["fix_id"], item["guard"]))
    for probe in health:
        print("close refmodel ident=%s ok=%s" % (probe["ident"], probe["ok"]))
    print("close verdict=%s triage=%s" % (verdict, triage))
    conn.close()
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cycle", type=int, required=True)
    ap.add_argument("--cycles-dir")
    ap.add_argument("--corpus")
    ap.add_argument("--config")
    ap.add_argument("--repo", help="the dedicated loop worktree to commit in")
    ap.add_argument("--applied-at", required=True,
                    help="date stamped into overlay entries (YYYY-MM-DD)")
    ap.add_argument("--probe-image",
                    help="one image, read by every enabled reference adapter")
    ap.add_argument("--regressive", nargs="*",
                    help="fix ids this run judged regressive; they enter the "
                         "denylist for every later cycle")
    ap.add_argument("--flagged", nargs="*",
                    help="foods whose metric did not decrease (Req 6.3)")
    return run(ap.parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())

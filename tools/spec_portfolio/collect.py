#!/usr/bin/env python3
"""Walk specs/ and emit one JSON record per spec for the portfolio renderer.

Usage: collect.py [OUTPUT_JSON]   (default /private/tmp/medata-portfolio/data.json)

Deterministic, stdlib only. Needs `rune` on PATH for task counts and `git`
for dates; a tasks file rune cannot parse is recorded as zeros plus a warning.
"""

import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SPECS = REPO / "specs"
DEFAULT_OUT = Path("/private/tmp/medata-portfolio/data.json")

SPEC_DOCS = {"requirements.md", "design.md", "smolspec.md", "prd.md", "report.md", "decision_log.md"}
SKIP_DIRS = {".orbit", "worktrees", "artifacts", "comparison-report", "diffs"}
AREAS = {"estimation", "ui", "data", "bugfixes"}
TODAY = dt.date.today()
ACTIVE_DAYS = 14
SUMMARY_MAX = 240
BACKLOG_TEXT_MAX = 160


# ---------------------------------------------------------------- helpers

def run(cmd, cwd=REPO):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=False)


def git_lines(*args):
    return [l for l in run(["git", *args]).stdout.splitlines() if l.strip()]


def strip_markdown(text):
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)  # links
    text = re.sub(r"`([^`]*)`", r"\1", text)                  # code
    text = re.sub(r"\*\*([^*]*)\*\*", r"\1", text)            # bold
    text = re.sub(r"(?<!\w)[*_]([^*_]+)[*_](?!\w)", r"\1", text)  # italics
    return re.sub(r"\s+", " ", text).strip()


def first_sentence(text):
    m = re.search(r"(?<=[.!?])\s+(?=[A-Z(\"'])", text)
    return text[: m.start()] if m else text


def truncate(text, limit):
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


# ---------------------------------------------------------------- summary

def first_paragraph(path, section=None):
    """First body paragraph of a markdown file, optionally after `## <section>`."""
    lines = path.read_text(encoding="utf-8").splitlines()
    if section:
        for i, line in enumerate(lines):
            if re.match(rf"^#+\s+{re.escape(section)}\b", line):
                lines = lines[i + 1:]
                break
    para = []
    for line in lines:
        s = line.strip()
        skip = (not s or s.startswith(("#", ">", "|", "<", "*(", "- ", "---"))
                or re.match(r"^\*\*[\w ]+:?\*\*:?", s))
        if skip:
            if para:
                break
            continue
        para.append(s)
    return " ".join(para)


def summary_for(folder):
    sources = [("requirements.md", None), ("smolspec.md", "Overview"), ("prd.md", None), ("report.md", None)]
    for name, section in sources:
        p = folder / name
        if p.exists():
            text = strip_markdown(first_paragraph(p, section))
            if text:
                return truncate(first_sentence(text), SUMMARY_MAX)
    return ""


# ---------------------------------------------------------------- tasks

def flatten(tasks):
    for t in tasks:
        yield t
        yield from flatten(t.get("Children") or [])


def collect_tasks(folder, task_files):
    counts = {"total": 0, "done": 0, "in_progress": 0, "pending": 0, "blocked": 0}
    pending, warnings = [], []
    for name in task_files:
        path = folder / name
        proc = run(["rune", "list", str(path), "-f", "json"])
        try:
            if proc.returncode != 0:
                raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "non-zero exit")
            data = json.loads(proc.stdout, strict=False)
            if not data.get("success", True):
                raise RuntimeError(data.get("error") or "rune reported failure")
            tasks = list(flatten(data.get("Tasks") or []))
        except Exception as exc:  # noqa: BLE001 - any failure must not stop the run
            warnings.append(f"{name}: rune could not parse ({str(exc).splitlines()[0][:120]})")
            continue
        status_by_id = {t["ID"]: t.get("Status", 0) for t in tasks}
        for t in tasks:
            status = t.get("Status", 0)
            counts["total"] += 1
            if status == 2:
                counts["done"] += 1
                continue
            counts["in_progress" if status == 1 else "pending"] += 1
            details = " ".join(t.get("Details") or [])
            open_deps = [d for d in (t.get("blockedBy") or []) if status_by_id.get(d) != 2]
            blocked = bool(open_deps) or "blocked" in f"{t['Title']} {details}".lower()
            counts["blocked"] += blocked
            pending.append({"file": name, "id": t["ID"], "title": t["Title"],
                            "phase": t.get("Phase") or None, "blocked": blocked})
    return counts, pending, warnings


# ---------------------------------------------------------------- decisions

STATUS_WORDS = ("superseded", "deprecated", "rejected", "proposed", "accepted", "amended")


def normalise_status(raw):
    s = raw.strip().lower()
    for word in STATUS_WORDS:
        if s.startswith(word):
            return "accepted" if word == "amended" else word
    return "accepted" if "accepted" in s else "proposed"


def parse_decisions(path):
    entries = []
    if not path.exists():
        return entries
    text = path.read_text(encoding="utf-8")
    heading = re.compile(r"^##\s+(Decision\s+\d+)\s*[:.—-]\s*(.+?)\s*$", re.MULTILINE)
    matches = list(heading.finditer(text))
    for i, m in enumerate(matches):
        body = text[m.end(): matches[i + 1].start() if i + 1 < len(matches) else len(text)]
        status = re.search(r"^\*\*Status\*\*:?\s*(.+)$|^\*\*Status:\*\*\s*(.+)$", body, re.MULTILINE)
        date = re.search(r"^\*\*Date\*\*:?\s*(\d{4}-\d{2}-\d{2})|^\*\*Date:\*\*\s*(\d{4}-\d{2}-\d{2})", body, re.MULTILINE)
        raw_status = (status.group(1) or status.group(2)) if status else "proposed"
        entries.append({"id": m.group(1), "title": strip_markdown(m.group(2)),
                        "status": normalise_status(raw_status),
                        "date": (date.group(1) or date.group(2)) if date else None})
    quick = re.search(r"^##\s+Quick Decisions\s*$(.*?)(?=^##\s|\Z)", text, re.MULTILINE | re.DOTALL)
    if quick:
        for row in quick.group(1).splitlines():
            cells = [c.strip() for c in row.strip().strip("|").split("|")] if row.strip().startswith("|") else []
            if len(cells) < 2 or not re.match(r"^Q\d+$", cells[0]):
                continue
            status_cell = next((c for c in cells[2:] if c.lower().startswith(STATUS_WORDS)), "accepted")
            date_cell = next((c for c in cells if re.match(r"^\d{4}-\d{2}-\d{2}$", c)), None)
            entries.append({"id": cells[0], "title": strip_markdown(cells[1]),
                            "status": normalise_status(status_cell), "date": date_cell})
    return entries


def decision_counts(entries):
    counts = {"total": len(entries), "proposed": 0, "accepted": 0, "rejected": 0, "superseded": 0,
              "quick": sum(1 for e in entries if e["id"].startswith("Q"))}
    for e in entries:
        if e["status"] in counts:
            counts[e["status"]] += 1
    return counts


# ---------------------------------------------------------------- backlog

def parse_backlog(path):
    """Return [(n, done, first_line, full_text)] for every numbered backlog item."""
    items = []
    if not path.exists():
        return items
    current = None
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^- \[( |x)\] (\d+)\. (.*)$", line)
        if m:
            current = [int(m.group(2)), m.group(1) == "x", m.group(3), [m.group(3)]]
            items.append(current)
        elif current is not None and line.startswith("  ") and line.strip():
            current[3].append(line.strip())
        elif current is not None and not line.strip():
            continue
        elif not line.startswith("  "):
            current = None
    return [(n, done, first, " ".join(full)) for n, done, first, full in items]


def backlog_refs(items, name, spec_id):
    pattern = re.compile(rf"(?<![\w-])(?:{re.escape(name)}|{re.escape(spec_id)})(?![\w-])", re.IGNORECASE)
    return [{"n": n, "done": done, "text": truncate(strip_markdown(first), BACKLOG_TEXT_MAX)}
            for n, done, first, full in items if pattern.search(full)]


# ---------------------------------------------------------------- git

def git_dates(folder):
    rel = str(folder.relative_to(REPO))
    last = git_lines("log", "-1", "--format=%cs", "--", rel)
    first = git_lines("log", "--diff-filter=A", "--format=%cs", "--", rel)
    dirty = git_lines("status", "--porcelain", "--", rel)
    last_touched = TODAY.isoformat() if dirty or not last else last[0]
    first_touched = first[-1] if first else last_touched
    commits_30d = len(git_lines("log", "--since=30.days", "--format=%h", "--", rel))
    return last_touched, first_touched, commits_30d


# ---------------------------------------------------------------- walk

def find_spec_folders():
    found = []

    def walk(d):
        names = sorted(p.name for p in d.iterdir())
        files = {n for n in names if (d / n).is_file()}
        is_spec = bool(files & SPEC_DOCS) or any(re.match(r"^tasks.*\.md$", n) for n in files)
        if is_spec and d != SPECS:
            found.append(d)
            return  # sub-folders of a spec (comparison-report, artifacts) belong to it
        for n in names:
            p = d / n
            if p.is_dir() and n not in SKIP_DIRS and not n.startswith("."):
                walk(p)

    walk(SPECS)
    return found


def collect_spec(folder, backlog):
    rel = folder.relative_to(SPECS)
    spec_id = rel.as_posix()
    top = rel.parts[0]
    files = sorted(p.name for p in folder.iterdir() if p.is_file() and p.name in SPEC_DOCS)
    task_files = sorted(p.name for p in folder.iterdir() if p.is_file() and re.match(r"^tasks.*\.md$", p.name))

    if top == "bugfixes" or "report.md" in files:
        kind = "bugfix"
    elif "smolspec.md" in files and "requirements.md" not in files:
        kind = "smolspec"
    else:
        kind = "feature"

    tasks, pending, warnings = collect_tasks(folder, task_files)
    decision_list = parse_decisions(folder / "decision_log.md")
    decisions = decision_counts(decision_list)
    last_touched, first_touched, commits_30d = git_dates(folder)

    if tasks["total"] > 0 and tasks["pending"] == 0 and tasks["in_progress"] == 0 and decisions["proposed"] == 0:
        state = "complete"
    elif (TODAY - dt.date.fromisoformat(last_touched)).days <= ACTIVE_DAYS:
        state = "active"
    else:
        state = "dormant"

    def doc(name):
        return f"specs/{spec_id}/{name}" if name in files else None

    record = {
        "id": spec_id,
        "name": folder.name,
        "area": top if top in AREAS else "other",
        "kind": kind,
        "summary": summary_for(folder),
        "files": files,
        "task_files": task_files,
        "tasks": tasks,
        "pending_tasks": pending,
        "decisions": decisions,
        "decision_list": decision_list,
        "last_touched": last_touched,
        "first_touched": first_touched,
        "commits_30d": commits_30d,
        "state": state,
        "backlog_refs": backlog_refs(backlog, folder.name, spec_id),
        "paths": {
            "folder": f"specs/{spec_id}",
            "requirements": doc("requirements.md"),
            "design": doc("design.md"),
            "decision_log": doc("decision_log.md"),
            "tasks": [f"specs/{spec_id}/{t}" for t in task_files],
        },
    }
    if warnings:
        record["warnings"] = warnings
    return record


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    backlog = parse_backlog(SPECS / "BACKLOG.md")
    specs = [collect_spec(f, backlog) for f in find_spec_folders()]
    # last_touched desc, then remaining tasks desc, then name asc (two stable sorts)
    specs.sort(key=lambda s: s["name"])
    specs.sort(key=lambda s: (s["last_touched"], s["tasks"]["pending"] + s["tasks"]["in_progress"]), reverse=True)

    totals = {
        "specs": len(specs),
        "complete": sum(s["state"] == "complete" for s in specs),
        "active": sum(s["state"] == "active" for s in specs),
        "dormant": sum(s["state"] == "dormant" for s in specs),
        "tasks_remaining": sum(s["tasks"]["pending"] + s["tasks"]["in_progress"] for s in specs),
        "decisions_proposed": sum(s["decisions"]["proposed"] for s in specs),
    }
    data = {
        "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "repo_head": run(["git", "rev-parse", "--short", "HEAD"]).stdout.strip(),
        "specs": specs,
        "totals": totals,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    width = max(len(s["id"]) for s in specs)
    print(f"{'spec':<{width}}  {'state':<8}  {'done/total':>10}  {'last':<10}  warn")
    for s in specs:
        print(f"{s['id']:<{width}}  {s['state']:<8}  {s['tasks']['done']:>4}/{s['tasks']['total']:<5}  "
              f"{s['last_touched']:<10}  {len(s.get('warnings', []))}")
    print(f"\ntotals: {json.dumps(totals)}\nwrote {out}")


if __name__ == "__main__":
    main()

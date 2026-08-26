#!/usr/bin/env python3
"""Pull a field session off the phone and ingest it (Req 3.3/3.4/3.7).

One command — `make field-pull` — does three things in order:

  1. copies `Documents/` off the device into `<corpus>/pulls/<UTC-date>-<n>/`,
     SHA-256ing every file as it lands;
  2. ingests that directory into the corpus and its index (`ingest.py`);
  3. pushes back a `pulled_manifest.json` naming what the Mac now verifiably
     holds, so the app can delete its copies (Decision 14).

`devicectl` has no recursive pull and no remote delete, which shapes both ends:
files are copied one `copy from` at a time (the wall-clock bottleneck on a
50 GB backlog — device-side slimming is the mitigation), and cleanup is a
manifest the app acts on rather than anything this tool can do directly.

The manifest handshake is two-phase on purpose. The manifest goes over under a
`.partial` name and only then a small sentinel carrying its SHA-256 and byte
length; `FieldMaintenance` acts only on a manifest whose sentinel verifies, so
a copy interrupted midway can never be read as a complete one.

The transport is injected so every other behaviour here is testable without a
phone: `--pull-dir` ingests a directory that is already on disk.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# Run either way: `python3 tools/field_loop/field_pull.py` (what the Makefile
# does) or `python3 -m field_loop.field_pull`. The bootstrap re-establishes the
# package identity the first form loses, so the relative imports below — and
# the ones inside the modules they pull in — resolve the same either way.
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    __package__ = "field_loop"

from . import corpus                                      # noqa: E402
from .ingest import ingest_pull                           # noqa: E402

DEFAULT_DEVICE = "6AD781BA-89FF-5A82-A2A1-B5EC9469F465"
DEFAULT_BUNDLE_ID = "rtob.MeData"

# Copied whole, with the siblings a live WAL database keeps its recent writes
# in. Pulling meals.sqlite alone gives a snapshot missing the session's last
# minutes — and PRAGMA integrity_check would not necessarily notice.
DB_FILES = ("meals.sqlite", "meals.sqlite-wal", "meals.sqlite-shm",
            "meals.sqlite-journal")
LOOSE_FILES = ("slimming_state.json",)


class DevicectlTransport:
    """The real device, one `devicectl` invocation at a time."""

    def __init__(self, device=DEFAULT_DEVICE, bundle_id=DEFAULT_BUNDLE_ID,
                 runner=subprocess.run):
        self.device = device
        self.bundle_id = bundle_id
        self.runner = runner

    def _base(self):
        return ["xcrun", "devicectl", "device", "--device", self.device]

    def list_files(self, subdirectory: str) -> list:
        import tempfile

        with tempfile.NamedTemporaryFile(suffix=".json") as out:
            self.runner(
                ["xcrun", "devicectl", "device", "info", "files",
                 "--device", self.device,
                 "--domain-type", "appDataContainer",
                 "--domain-identifier", self.bundle_id,
                 "--subdirectory", subdirectory,
                 "--json-output", out.name],
                check=True, capture_output=True, text=True)
            payload = json.loads(Path(out.name).read_text())
        return _flatten_listing(payload, subdirectory)

    def copy_from(self, remote: str, local: Path) -> bool:
        local.parent.mkdir(parents=True, exist_ok=True)
        result = self.runner(
            ["xcrun", "devicectl", "device", "copy", "from",
             "--device", self.device,
             "--domain-type", "appDataContainer",
             "--domain-identifier", self.bundle_id,
             "--source", remote, "--destination", str(local)],
            capture_output=True, text=True)
        return result.returncode == 0

    def copy_to(self, local: Path, remote: str) -> bool:
        result = self.runner(
            ["xcrun", "devicectl", "device", "copy", "to",
             "--device", self.device,
             "--domain-type", "appDataContainer",
             "--domain-identifier", self.bundle_id,
             "--source", str(local), "--destination", remote],
            capture_output=True, text=True)
        return result.returncode == 0


def _flatten_listing(payload, subdirectory):
    """Relative paths from a `devicectl info files` JSON tree.

    devicectl has changed this envelope's shape between releases, so the walk
    is structural — anything carrying a name and no children is a file — rather
    than keyed on a schema version that would break on the next Xcode.
    """
    found = []

    def walk(node, prefix):
        if isinstance(node, list):
            for item in node:
                walk(item, prefix)
            return
        if not isinstance(node, dict):
            return
        name = node.get("name") or node.get("path")
        children = node.get("files") or node.get("contents") or node.get("children")
        here = "%s/%s" % (prefix, name) if name and prefix else (name or prefix)
        if children:
            walk(children, here)
        elif name:
            found.append(here)
        else:
            for value in node.values():
                if isinstance(value, (list, dict)):
                    walk(value, prefix)

    walk(payload, subdirectory.rstrip("/"))
    return sorted(set(found))


def next_pull_id(root: Path, now=None) -> str:
    """`<UTC-date>-<n>`: sortable, and countable within a day."""
    day = (now or datetime.now(timezone.utc)).strftime("%Y%m%d")
    existing = [p.name for p in (root / "pulls").glob("%s-*" % day)]
    return "%s-%d" % (day, len(existing) + 1)


def pull_files(transport, pull_dir: Path) -> dict:
    """Copy `Documents/` down. Returns {relative path: sha256}."""
    hashes = {}
    wanted = []
    for subdirectory in ("Documents/notes", "Documents/captures"):
        try:
            wanted.extend(transport.list_files(subdirectory))
        except subprocess.CalledProcessError:
            continue                    # the directory does not exist yet
    wanted.extend("Documents/%s" % name for name in DB_FILES + LOOSE_FILES)

    for remote in wanted:
        relative = remote[len("Documents/"):]
        local = pull_dir / relative
        if not transport.copy_from(remote, local):
            continue                    # optional file (WAL sibling, state json)
        if local.is_file():
            hashes[relative] = corpus.sha256_file(local)
    return hashes


def build_manifest(conn, pull_id: str, hashes: dict) -> dict:
    """What the phone may now delete.

    A bundle or note is listed only with the hash the Mac verified; the app
    re-hashes before deleting, so a file that changed since the pull survives.
    An outcome id is listed only once EVERY note referencing it is in the
    corpus and in this pull — the device cannot know that, and unprotecting an
    outcome a still-on-phone note points at would let it evict.
    """
    bundles = [{"stem": Path(name).stem, "sha256": digest}
               for name, digest in sorted(hashes.items())
               if name.startswith("captures/") and name.endswith(".fixture")]
    notes = [{"stem": Path(name).stem, "sha256": digest}
             for name, digest in sorted(hashes.items())
             if name.startswith("notes/")]

    retire = []
    for row in conn.execute("SELECT outcome_id FROM protections ORDER BY outcome_id"):
        outcome_id = row["outcome_id"]
        referencing = conn.execute(
            "SELECT pull_id FROM notes WHERE outcome_id = ?", (outcome_id,)).fetchall()
        if referencing and all(r["pull_id"] == pull_id for r in referencing):
            retire.append(outcome_id)
    return {"pull_id": pull_id, "bundles": bundles, "notes": notes,
            "protected_outcomes": retire}


def push_manifest(transport, manifest: dict, staging: Path) -> bool:
    """Manifest first under its `.partial` name, sentinel second. Order is the
    whole safety property: the sentinel is what makes a manifest actionable."""
    import hashlib

    staging.mkdir(parents=True, exist_ok=True)
    body = json.dumps(manifest, sort_keys=True).encode()
    manifest_path = staging / corpus.MANIFEST_NAME
    manifest_path.write_bytes(body)
    sentinel_path = staging / corpus.SENTINEL_NAME
    sentinel_path.write_text(json.dumps(
        {"sha256": hashlib.sha256(body).hexdigest(), "length": len(body)},
        sort_keys=True))

    if not transport.copy_to(manifest_path, "Documents/%s" % corpus.MANIFEST_NAME):
        return False
    return transport.copy_to(sentinel_path, "Documents/%s" % corpus.SENTINEL_NAME)


def run(args, transport=None) -> int:
    root = corpus.ensure_layout(
        Path(args.corpus) if args.corpus else corpus.corpus_root())
    conn = corpus.open_index(root)

    if args.pull_dir:
        pull_dir = Path(args.pull_dir)
        hashes = {}
    else:
        transport = transport or DevicectlTransport(args.device, args.bundle_id)
        pull_dir = root / "pulls" / next_pull_id(root)
        pull_dir.mkdir(parents=True, exist_ok=True)
        hashes = pull_files(transport, pull_dir)

    summary = ingest_pull(pull_dir, root, conn)
    for line in summary.lines():
        print(line)

    if args.prune and transport is not None:
        manifest = build_manifest(conn, summary.pull_id, hashes)
        pushed = push_manifest(transport, manifest, pull_dir / "manifest")
        print("pull manifest_pushed=%s bundles=%d notes=%d unprotected=%d"
              % (str(pushed).lower(), len(manifest["bundles"]),
                 len(manifest["notes"]), len(manifest["protected_outcomes"])))
    elif args.prune:
        print("pull manifest_pushed=false reason=no_device_transport")

    print("corpus root=%s bytes=%d captures=%d notes=%d"
          % (root, corpus.directory_bytes(root),
             conn.execute("SELECT count(*) FROM captures").fetchone()[0],
             conn.execute("SELECT count(*) FROM notes").fetchone()[0]))
    print(corpus.SINGLE_COPY_ACCEPTANCE)
    conn.close()
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--device", default=os.environ.get("DEVICE_UDID", DEFAULT_DEVICE))
    ap.add_argument("--bundle-id", default=os.environ.get("BUNDLE_ID", DEFAULT_BUNDLE_ID))
    ap.add_argument("--corpus", help="override the resolved corpus root")
    ap.add_argument("--pull-dir",
                    help="ingest an existing pull directory instead of pulling")
    ap.add_argument("--prune", action="store_true",
                    help="push the cleanup manifest back to the device (Req 3.7)")
    return run(ap.parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())

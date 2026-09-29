#!/usr/bin/env python3
"""Reclaim the space the field loop accumulates, on the Mac side.

`medata-corpus/captures/` is the loop's whole footprint — tens of gigabytes of
`.fixture` bundles — and the only thing it buys is re-derivation: replaying a
capture through a newer checkpoint. Notes, the per-pull database snapshots and
`index.sqlite` together are three orders of magnitude smaller and are what the
triage ledger and the alignment report are computed from, so this deletes the
first and keeps the rest.

The index rows stay. Every consumer already guards on the fixture existing
(`field_diagnose.replay`, `derive_dataset`), so a discarded capture is skipped
rather than fatal, and `field_report`'s denominators keep counting a capture that
really happened. An index that forgot it would make the alignment figures look
better than the truth.

The device side is not here: `FieldMaintenance` deletes a bundle only when the
pulled manifest carries its SHA-256, and the Mac cannot know that hash without
reading the file. Clearing the phone quickly is therefore a container wipe, which
`make field-discard` drives around this — see docs/build-and-field-loop.md.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import corpus  # noqa: E402


def survey(root: Path) -> dict:
    """What is about to be deleted, and what is about to survive."""
    captures = root / "captures"
    conn = corpus.open_index(root)
    try:
        indexed = conn.execute("SELECT count(*) FROM captures").fetchone()[0]
        notes = conn.execute("SELECT count(*) FROM notes").fetchone()[0]
    finally:
        conn.close()
    return {
        "capture_files": len(list(captures.glob("*.fixture"))) if captures.exists() else 0,
        "capture_bytes": corpus.directory_bytes(captures) if captures.exists() else 0,
        "indexed_captures": indexed,
        "notes": notes,
        "notes_bytes": corpus.directory_bytes(root / "notes"),
        "db_bytes": corpus.directory_bytes(root / "db"),
    }


def discard(root: Path) -> None:
    """Delete the capture bundles and the raw pull directories they came from.

    `pulls/` holds the wire copies the ingest hard-linked into `captures/`, so
    leaving it would leave the bytes behind under another name.
    """
    for name in ("captures", "pulls"):
        target = root / name
        if target.exists():
            shutil.rmtree(target)
    corpus.ensure_layout(root)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--corpus", help="override the resolved corpus root")
    ap.add_argument("--confirm", default="",
                    help="must be 'yes'; without it nothing is deleted")
    args = ap.parse_args(argv)

    root = Path(args.corpus) if args.corpus else corpus.corpus_root()
    root = corpus.ensure_layout(root)
    before = survey(root)

    print("discard root=%s" % root)
    print("discard deletes captures=%d bytes=%d pulls_bytes=%d"
          % (before["capture_files"], before["capture_bytes"],
             corpus.directory_bytes(root / "pulls")))
    print("discard keeps notes=%d notes_bytes=%d db_bytes=%d index_rows=%d"
          % (before["notes"], before["notes_bytes"], before["db_bytes"],
             before["indexed_captures"]))

    if args.confirm != "yes":
        print("discard refused=missing_confirmation "
              "hint='rerun with CONFIRM=yes — this cannot be undone'")
        return 1

    discard(root)
    after = survey(root)
    print("discard done freed_bytes=%d captures_remaining=%d index_rows=%d"
          % (before["capture_bytes"] - after["capture_bytes"],
             after["capture_files"], after["indexed_captures"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

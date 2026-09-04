"""Shared fixtures/setup for the food-db tool tests.

Three independent needs are served here:

- ``test_bake_lock.py`` imports generate.py as a plain module. generate.py is a
  standalone script, not a package, so the test dir's parent is added to sys.path.
  Importing it must have NO side effects (it must not bake the DBs) — the bake runs
  only under ``if __name__ == "__main__"``.
- ``test_generate.py`` reads the committed cofid_db.sqlite directly. The density
  bug it guards lives in the *shipped* artifact, so the fix only goes green once
  generate.py is corrected AND re-run.
- Every test here needs the loop overlay out of the way by default — see
  ``overlay_absent`` below.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import generate  # noqa: E402  (needs the sys.path insert above)

REPO_ROOT = Path(__file__).resolve().parents[3]
COFID_DB = REPO_ROOT / "MedataCore" / "Sources" / "Foods" / "Resources" / "cofid_db.sqlite"


@pytest.fixture(scope="session")
def cofid_db_path() -> Path:
    assert COFID_DB.exists(), f"bundled CoFID DB not found at {COFID_DB}"
    return COFID_DB


@pytest.fixture(autouse=True)
def overlay_absent(tmp_path, monkeypatch):
    """Point generate.OVERLAY_JSON at a path that does not exist, for every
    test in this directory.

    The loop overlay is read from a fixed committed path by default
    (ml-feedback-loop Req 5.1), so once the feedback loop lands its first fix
    every temp-dir bake here would silently pick it up and the source-value
    assertions would start failing on a change that is not theirs. Tests about
    the overlay redirect this again to a file they write themselves.
    """
    monkeypatch.setattr(generate, "OVERLAY_JSON",
                        str(tmp_path / "no-such-overlay.json"))

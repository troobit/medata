"""Shared fixtures/setup for the food-db tool tests.

Two independent needs are served here:

- ``test_bake_lock.py`` imports generate.py as a plain module. generate.py is a
  standalone script, not a package, so the test dir's parent is added to sys.path.
  Importing it must have NO side effects (it must not bake the DBs) — the bake runs
  only under ``if __name__ == "__main__"``.
- ``test_generate.py`` reads the committed cofid_db.sqlite directly. The density
  bug it guards lives in the *shipped* artifact, so the fix only goes green once
  generate.py is corrected AND re-run.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

REPO_ROOT = Path(__file__).resolve().parents[3]
COFID_DB = REPO_ROOT / "MedataCore" / "Sources" / "Foods" / "Resources" / "cofid_db.sqlite"


@pytest.fixture(scope="session")
def cofid_db_path() -> Path:
    assert COFID_DB.exists(), f"bundled CoFID DB not found at {COFID_DB}"
    return COFID_DB

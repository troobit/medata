"""Locate the bundled CoFID database for the food-db regression tests.

generate.py is a standalone script that bakes the SQLite artifacts under
MedataCore/Sources/Foods/Resources/. The bug being guarded here lives in the
*shipped* artifact, so the tests read the committed cofid_db.sqlite directly —
which means the fix only goes green once generate.py is corrected AND re-run.
"""

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
COFID_DB = REPO_ROOT / "MedataCore" / "Sources" / "Foods" / "Resources" / "cofid_db.sqlite"


@pytest.fixture(scope="session")
def cofid_db_path() -> Path:
    assert COFID_DB.exists(), f"bundled CoFID DB not found at {COFID_DB}"
    return COFID_DB

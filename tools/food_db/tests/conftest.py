"""Make generate.py importable as a plain module in tests.

generate.py is a standalone script, not a package, so the test dir's parent is
added to sys.path. Importing it must have NO side effects (it must not bake the
DBs) — the bake runs only under ``if __name__ == "__main__"`` — so these tests
exercise the palette-lock predicate without touching cofid_db.sqlite.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

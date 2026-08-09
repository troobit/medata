"""Make the sibling tool modules (mapping.py, build_mapping.py, render.py,
ingest.py) and the shared test helpers importable (mirrors
tools/nutrition5k/tests).

The metafood3d tools are standalone scripts, not a package: the test dir's
parent is added to sys.path and they import as plain modules. The test dir
itself is added so helpers import under the unique name ``mf3d_testkit``
(``conftest`` is not importable by name — every test dir has one).
"""

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))
sys.path.insert(0, str(_HERE))

"""Make the sibling tool modules (export.py, lineage.py) importable in tests.

The segmenter tools are standalone scripts, not a package, so the test dir's
parent is added to sys.path and they import as plain modules. Importing export.py
does NOT pull in torch/coremltools (those are lazy), so the gate tests run without
the heavy training dependencies installed.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

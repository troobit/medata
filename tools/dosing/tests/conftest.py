"""`retrospective.py` is a standalone script, not a package, so the tool
directory goes on sys.path before the tests import it.

Importing it must have no side effects — the measurement runs only under
``if __name__ == "__main__"``.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

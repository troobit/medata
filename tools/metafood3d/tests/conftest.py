"""Make the shared test helpers importable under the unique name
``mf3d_testkit`` (``conftest`` is not importable by name — every tool test
dir has one).

Deliberately UNLIKE tools/nutrition5k/tests: the tool dir itself is NOT
put on sys.path. The metafood3d file names (mapping.py, ingest.py, ...)
mirror tools/nutrition5k per the design parity table, so exposing this
dir to plain ``import mapping`` / ``import ingest`` would shadow the
nutrition5k modules when several tool test dirs run in one pytest
invocation. Tests import the tool modules through
``mf3d_testkit.load_tool`` (unique ``metafood3d_<name>`` module keys).
"""

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))

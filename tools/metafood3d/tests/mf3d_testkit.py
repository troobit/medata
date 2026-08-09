"""Shared helpers for the metafood3d tool tests.

Helpers live here, not ``conftest.py`` — ``from conftest import ...`` breaks
when several tool test dirs run in one pytest invocation (module-name
collision; same convention as tools/nutrition5k/tests/n5k_testkit.py).

``load_tool`` imports a sibling tool module under a unique
``metafood3d_<name>`` sys.modules key: the design-mandated file names
(mapping.py, build_mapping.py, render.py, ingest.py) mirror
tools/nutrition5k/, so a plain ``import mapping`` would collide with the
nutrition5k modules when both test dirs run in one invocation.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parents[1]


def load_tool(name: str):
    """Import tools/metafood3d/<name>.py under the collision-proof
    ``metafood3d_<name>`` module key (idempotent)."""
    key = f"metafood3d_{name}"
    if key in sys.modules:
        return sys.modules[key]
    path = _TOOL_DIR / f"{name}.py"
    spec = importlib.util.spec_from_file_location(key, path)
    assert spec is not None and spec.loader is not None, path
    module = importlib.util.module_from_spec(spec)
    sys.modules[key] = module
    spec.loader.exec_module(module)
    return module

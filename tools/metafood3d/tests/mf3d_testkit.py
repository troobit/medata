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

import csv
import importlib.util
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parents[1]
_REPO_ROOT = _TOOL_DIR.parents[1]
SCHEMA_DIR = (_REPO_ROOT / "MedataCore" / "Sources" / "PortableContracts"
              / "Schemas")


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


def load_make_fixtures():
    """tools/segmenter/make_fixtures.py under a unique key (for parsing the
    emitted .fixture protos back in tests)."""
    key = "metafood3d_tests_make_fixtures"
    if key in sys.modules:
        return sys.modules[key]
    path = _REPO_ROOT / "tools" / "segmenter" / "make_fixtures.py"
    spec = importlib.util.spec_from_file_location(key, path)
    assert spec is not None and spec.loader is not None, path
    module = importlib.util.module_from_spec(spec)
    sys.modules[key] = module
    spec.loader.exec_module(module)
    return module


def parse_fixture(data: bytes):
    """Deserialise .fixture bytes into a PbMealFixture message."""
    mf = load_make_fixtures()
    pb = mf._import_meal_fixture_pb(SCHEMA_DIR)
    fx = pb.MealFixture()
    fx.ParseFromString(data)
    return fx


def write_dataset(root: Path, objects) -> Path:
    """Materialise a synthetic MetaFood3D-layout dataset directory.

    ``objects``: iterable of (object_id, category, weight_g, trimesh mesh).
    Layout per the ingest docstring: ``meshes/<category>/<object_id>.obj``
    plus ``metadata.csv`` (object_id, category, weight_g)."""
    root.mkdir(parents=True, exist_ok=True)
    rows = []
    for object_id, category, weight_g, mesh in objects:
        mesh_dir = root / "meshes" / category
        mesh_dir.mkdir(parents=True, exist_ok=True)
        (mesh_dir / f"{object_id}.obj").write_text(
            mesh.export(file_type="obj"))
        rows.append((object_id, category, weight_g))
    with open(root / "metadata.csv", "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["object_id", "category", "weight_g"])
        writer.writerows(rows)
    return root

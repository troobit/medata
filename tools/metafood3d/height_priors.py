"""Per-class food HEIGHT prior from the MetaFood3D meshes.

Reads every mesh under ``<mesh-root>/<Category>/<object>/*.obj`` (the
shipped archive layout, ``.obj`` only — textures are not needed), seats it
on its support plane (z = 0, food in +z), measures its height distribution,
footprint and closed volume, joins the nutrition workbook's weight/volume
columns, and aggregates per PALETTE class through
``mapping_metafood3d_to_palette.json``. Output: ``height_priors.json``
(schema ``height_priors.v1``) plus a per-item CSV for auditing.

Base-plane rule (``seat_on_base``): the scanner frame is gravity-aligned
(its z axis is vertical, sign not consistent between scans), so the base is
the LARGEST convex-hull facet whose normal lies within ``SEAT_CONE_DEG`` of
the raw +z or -z axis. The mesh is rotated so that facet faces -z and
translated so it lies on z = 0. The cone is what makes the rule robust: an
unconstrained largest-facet rule seats a chicken breast or a rice bowl on
its side whenever a side facet happens to be the largest (measured on this
snapshot: 5 of 97 mapped meshes read 1.4-2.2x too tall that way). Only the
height above the seat matters here, so an upside-down seat (a flat slice
scanned base-up) changes nothing the prior reads. ``raw_z_extent_mm`` and
``seat_tilt_deg`` in the item CSV are the cross-check: a seat that tilts
more than a few degrees from the scanner vertical and changes the height
is a mesh whose scan frame was itself tilted.

Deterministic: numpy + trimesh (qhull convex hull), no randomness, CPU only.

Usage:
    tools/metafood3d/.venv/bin/python tools/metafood3d/height_priors.py \\
        [--mesh-root data/metafood3d/3D_Mesh] [--limit N]
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import importlib.util
import json
import logging
import re
import sys
import time
from pathlib import Path

import numpy as np
import trimesh
from trimesh.exchange.obj import load_obj

_HERE = Path(__file__).resolve().parent
_REPO_ROOT = _HERE.parents[1]

DEFAULT_MESH_ROOT = _REPO_ROOT / "data" / "metafood3d" / "3D_Mesh"
DEFAULT_WORKBOOK = (
    _REPO_ROOT / "data" / "_MetaFood3D_new_complete_dataset_nutrition_v2.xlsx")
DEFAULT_MAPPING = _HERE / "mapping_metafood3d_to_palette.json"
DEFAULT_OUT_JSON = _HERE / "height_priors.json"
DEFAULT_OUT_CSV = _HERE / "height_priors_items.csv"

SCHEMA = "height_priors.v1"
SOURCE = "MetaFood3D 3D_Mesh"

# The meshes are authored in metres (median max-extent ~0.1). Anything
# outside this band means a different snapshot or unit — abort, do not guess.
METRES_MAX_EXTENT_BAND = (0.02, 0.6)
MM_PER_M = 1000.0

# Workbook typos: the nutrition sheet spells two object ids differently
# from their mesh directories. Keyed by (normalised category, workbook id).
WORKBOOK_ID_FIXES = {
    ("carrot", "carrrot_8"): "carrot_8",
    ("edamame", "new_edammame_4"): "new_edamame_4",
}

# Height-only extensions to the beta-fit mapping. The mapping artifact
# marks Rice and Yeast_bread AMBIGUOUS because the palette splits them by
# a property (grain colour, flour) that the mass fit needs and a height
# prior does not: a mound of rice is the same height whichever rice it is.
# Every category here is listed under ``height_only_categories`` in the
# output so the strict-mapping count stays visible.
HEIGHT_ONLY_EXTENSIONS = {
    "rice": ("white_rice", "brown_rice"),
    "yeast_bread": ("bread_white", "bread_wholemeal"),
}

# Hull facets whose normal tilts more than this from the scanner's vertical
# (raw +z or -z) are not candidate bases.
SEAT_CONE_DEG = 30.0

# Top-surface height field raster cell (mm). Matches the order of the
# 3 mm carve voxel without quantising the percentiles to it.
CELL_MM = 2.0

# Palette sentinels (background, unknown food, unsupported liquid) carry
# no height; listed so the file covers every palette index.
SENTINELS = ("background", "unknown_food", "unsupported_liquid")


def _import_sibling(name: str):
    key = f"metafood3d_{name}"
    if key in sys.modules:
        return sys.modules[key]
    spec = importlib.util.spec_from_file_location(key, _HERE / f"{name}.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[key] = module
    spec.loader.exec_module(module)
    return module


mapping = _import_sibling("mapping")
derive_metadata = _import_sibling("derive_metadata")


# --------------------------------------------------------------------------- #
# Mesh loading and seating.
# --------------------------------------------------------------------------- #
def load_mesh(path: Path) -> trimesh.Trimesh:
    """Vertices and faces only. ``trimesh.load`` would try to copy the OBJ's
    material through PIL, which this venv deliberately does not carry."""
    with open(path, "rb") as fh:
        kw = load_obj(fh, skip_materials=True, maintain_order=False)
    if "geometry" in kw:  # multi-group OBJ: concatenate the groups
        parts = [trimesh.Trimesh(vertices=g["vertices"], faces=g["faces"],
                                 process=False)
                 for g in kw["geometry"].values()]
        return trimesh.util.concatenate(parts)
    return trimesh.Trimesh(vertices=kw["vertices"], faces=kw["faces"],
                           process=False)


def seat_on_base(mesh: trimesh.Trimesh) -> tuple[trimesh.Trimesh, dict]:
    """Rotate/translate a copy so the largest convex-hull facet within
    ``SEAT_CONE_DEG`` of the scanner vertical lies on z = 0 with the body in
    +z. Returns the seated mesh and diagnostics."""
    hull = mesh.convex_hull
    normals = hull.facets_normal                        # outward, unit
    tilt = np.degrees(np.arccos(np.clip(np.abs(normals[:, 2]), 0.0, 1.0)))
    cone = np.flatnonzero(tilt <= SEAT_CONE_DEG)
    if cone.size == 0:                                  # not seen; keep total
        cone = np.arange(len(normals))
    i = int(cone[np.argmax(hull.facets_area[cone])])
    normal = normals[i]
    # Rotate so that ``normal`` maps onto -z.
    rot = trimesh.geometry.align_vectors(normal, [0.0, 0.0, -1.0])
    seated = mesh.copy()
    seated.apply_transform(rot)
    # The facet is the lowest plane of the hull after rotation.
    seated.apply_translation([0.0, 0.0, -float(seated.bounds[0][2])])
    diag = {
        "base_facet_area_mm2": float(hull.facets_area[i]),
        "seat_tilt_deg": float(tilt[i]),
        # Height the raw (as-scanned) frame would give, for the rule check.
        "raw_z_extent_mm": float(mesh.extents[2]),
    }
    return seated, diag


def closed_volume_mm3(seated: trimesh.Trimesh) -> float:
    """Signed-tetrahedra volume with the origin ON the base plane, so a mesh
    left open at its table cut is closed by that plane. Equals
    ``trimesh.volume`` for a watertight mesh."""
    v = seated.vertices[seated.faces]
    return float(abs(np.einsum("ij,ij->i", v[:, 0],
                               np.cross(v[:, 1], v[:, 2])).sum()) / 6.0)


def measure(seated: trimesh.Trimesh, cell_mm: float) -> dict:
    z = seated.vertices[:, 2]
    # Top-surface height field: max z per xy cell — the shape a nadir depth
    # sensor sees, and the footprint without a convex-hull overestimate.
    xy = np.floor(seated.vertices[:, :2] / cell_mm).astype(np.int64)
    xy -= xy.min(axis=0)
    flat = xy[:, 0] * (xy[:, 1].max() + 1) + xy[:, 1]
    top = np.full(flat.max() + 1, -np.inf)
    np.maximum.at(top, flat, z)
    top = top[np.isfinite(top)]
    return {
        "max_height_mm": float(z.max()),
        "p98_height_mm": float(np.percentile(z, 98)),
        "p90_height_mm": float(np.percentile(z, 90)),
        "p50_height_mm": float(np.percentile(z, 50)),
        "surface_p90_mm": float(np.percentile(top, 90)),
        "surface_p50_mm": float(np.percentile(top, 50)),
        "footprint_cm2": float(top.size * cell_mm * cell_mm / 100.0),
        "extent_x_mm": float(seated.extents[0]),
        "extent_y_mm": float(seated.extents[1]),
        "volume_cm3": closed_volume_mm3(seated) / 1000.0,
        "watertight": bool(seated.is_watertight),
    }


# --------------------------------------------------------------------------- #
# Inputs.
# --------------------------------------------------------------------------- #
def find_meshes(root: Path) -> list[tuple[str, str, Path]]:
    """(category_dir, object_dir, obj_path) for every object directory that
    holds exactly one .obj, sorted for determinism."""
    if not root.is_dir():
        raise SystemExit(f"[height_priors] mesh root not found: {root}\n"
                         f"  tar -xzf data/_MetaFood3D_new_3D_Mesh.tar.gz "
                         f"-C data/metafood3d --include='*.obj'")
    found = []
    for cat in sorted(p for p in root.iterdir() if p.is_dir()):
        for obj in sorted(p for p in cat.iterdir() if p.is_dir()):
            objs = sorted(obj.glob("*.obj"))
            if len(objs) != 1:
                raise SystemExit(f"[height_priors] {obj}: expected one .obj, "
                                 f"found {len(objs)}")
            found.append((cat.name, obj.name, objs[0]))
    return found


def read_workbook(path: Path) -> dict[tuple[str, str], dict]:
    """{(normalised category, object dir): {weight_g, volume_cm3}}."""
    rows = derive_metadata.read_rows(path)
    header = rows[0]
    if header != derive_metadata.EXPECTED_HEADER:
        raise SystemExit(f"[height_priors] unexpected workbook header {header}")
    out = {}
    norm = mapping.normalise_category
    for row in rows[1:]:
        row = row + [""] * (len(header) - len(row))
        cat, obj = norm(row[0]), norm(row[1])
        obj = WORKBOOK_ID_FIXES.get((cat, obj), obj)
        out[(cat, obj)] = {
            "weight_g": float(row[3]) if row[3].strip() else None,
            "volume_cm3": float(row[8]) if row[8].strip() else None,
        }
    return out


def class_targets(category: str, mp) -> tuple[list[str], bool]:
    """Palette classes a category contributes height to, and whether that
    comes from the strict mapping (True) or a height-only extension."""
    strict = mp.class_for(category)
    if strict is not None:
        return [strict], True
    ext = HEIGHT_ONLY_EXTENSIONS.get(mapping.normalise_category(category))
    return (list(ext), False) if ext else ([], True)


# --------------------------------------------------------------------------- #
# Aggregation.
# --------------------------------------------------------------------------- #
def _pct(values: list[float], q: float) -> float | None:
    return float(np.percentile(values, q)) if values else None


def _r(x: float | None, nd: int = 1) -> float | None:
    return None if x is None else round(x, nd)


def aggregate(palette: list[str], items: list[dict]) -> dict:
    classes: dict[str, dict] = {}
    for index, name in enumerate(palette + list(SENTINELS)):
        mine = [it for it in items if name in it["classes"]]
        entry: dict = {"index": index, "n_items": len(mine)}
        if name in SENTINELS:
            entry.update(n_items=0, note="palette sentinel, not a food")
        elif not mine:
            entry["note"] = "no MetaFood3D category maps to this class"
        if mine:
            mx = [it["max_height_mm"] for it in mine]
            entry.update({
                "n_items_strict_mapping": sum(it["strict"] for it in mine),
                "categories": sorted({it["category"] for it in mine}),
                "max_height_p50_mm": _r(_pct(mx, 50)),
                "max_height_p90_mm": _r(_pct(mx, 90)),
                "max_height_min_mm": _r(min(mx)),
                "max_height_max_mm": _r(max(mx)),
                "p98_height_p50_mm": _r(_pct([it["p98_height_mm"] for it in mine], 50)),
                "surface_p50_p50_mm": _r(_pct([it["surface_p50_mm"] for it in mine], 50)),
                "footprint_cm2_p50": _r(_pct([it["footprint_cm2"] for it in mine], 50)),
                "volume_cm3_p50": _r(_pct([it["volume_cm3"] for it in mine], 50)),
            })
        classes[name] = entry
    return classes


# --------------------------------------------------------------------------- #
# Main.
# --------------------------------------------------------------------------- #
def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--mesh-root", type=Path, default=DEFAULT_MESH_ROOT)
    ap.add_argument("--workbook", type=Path, default=DEFAULT_WORKBOOK)
    ap.add_argument("--mapping", type=Path, default=DEFAULT_MAPPING)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT_JSON)
    ap.add_argument("--items-csv", type=Path, default=DEFAULT_OUT_CSV)
    ap.add_argument("--limit", type=int, default=None,
                    help="smoke run: first N meshes in sorted order")
    ap.add_argument("--cell-mm", type=float, default=CELL_MM)
    args = ap.parse_args(argv)

    logging.getLogger("trimesh").setLevel(logging.ERROR)
    t0 = time.time()

    palette = mapping.parse_palette().class_list
    mp = mapping.load_mapping(args.mapping, expected_palette_class_list=palette)
    workbook = read_workbook(args.workbook)
    meshes = find_meshes(args.mesh_root)
    if args.limit:
        meshes = meshes[: args.limit]

    items: list[dict] = []
    max_extents_m: list[float] = []
    for n, (cat, obj, path) in enumerate(meshes, start=1):
        mesh = load_mesh(path)
        max_extents_m.append(float(mesh.extents.max()))
        mesh.apply_scale(MM_PER_M)
        seated, diag = seat_on_base(mesh)
        classes, strict = class_targets(cat, mp)
        key = (mapping.normalise_category(cat), mapping.normalise_category(obj))
        wb = workbook.get(key, {"weight_g": None, "volume_cm3": None})
        item = {
            "category": cat, "object": obj, "classes": classes,
            "strict": strict, "vertices": len(mesh.vertices),
            "weight_g": wb["weight_g"], "workbook_volume_cm3": wb["volume_cm3"],
            "in_workbook": key in workbook,
        }
        item.update(measure(seated, args.cell_mm))
        item.update(diag)
        items.append(item)
        if n % 25 == 0 or n == len(meshes):
            print(f"[height_priors] {n}/{len(meshes)} {time.time() - t0:.0f}s",
                  file=sys.stderr)

    med = float(np.median(max_extents_m))
    lo, hi = METRES_MAX_EXTENT_BAND
    if not lo <= med <= hi:
        raise SystemExit(f"[height_priors] median max extent {med:.3f} is "
                         f"outside the metre band {METRES_MAX_EXTENT_BAND}; "
                         f"the snapshot is not in the units this tool assumes")

    classes = aggregate(palette, items)
    all_max = [it["max_height_mm"] for it in items]
    out = {
        "schema": SCHEMA,
        "source": SOURCE,
        "units": "mm",
        "generated": dt.date.today().isoformat(),
        "base_plane_rule": (f"largest convex-hull facet within {SEAT_CONE_DEG:.0f} deg "
                            f"of the scanner vertical (raw +/-z) on z=0, body in +z"),
        "seat_cone_deg": SEAT_CONE_DEG,
        "n_meshes": len(items),
        "n_meshes_mapped": sum(bool(it["classes"]) for it in items),
        "height_only_categories": sorted(HEIGHT_ONLY_EXTENSIONS),
        "global": {
            "max_height_p50_mm": _r(_pct(all_max, 50)),
            "max_height_p90_mm": _r(_pct(all_max, 90)),
            "max_height_p98_mm": _r(_pct(all_max, 98)),
        },
        "classes": classes,
    }
    args.out.write_text(json.dumps(out, indent=2) + "\n")

    fields = [k for k in items[0] if k != "classes"] + ["classes"]
    with open(args.items_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        for it in items:
            row = {k: (round(v, 2) if isinstance(v, float) else v)
                   for k, v in it.items()}
            row["classes"] = "|".join(it["classes"])
            w.writerow(row)

    print(f"[height_priors] {len(items)} meshes, {out['n_meshes_mapped']} mapped, "
          f"median max extent {med * MM_PER_M:.0f} mm, {time.time() - t0:.0f}s "
          f"-> {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

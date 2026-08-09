#!/usr/bin/env python3
"""Bridge MetaFood3D single-food meshes into MeData ``.fixture`` files
(Req 1.1/1.2/1.5, Decisions 11/13/14/15).

Mirrors ``tools/nutrition5k/ingest.py`` and reuses
``tools/segmenter/make_fixtures.build_fixture_bytes`` so the proto-writing
path stays a single pure function. Every mapped object is emitted as
exactly one **mixture** fixture: ``estimator_path = "mixture"``,
``segmenter_checkpoint_sha256 = "no_segmenter"``, NO probability tensor
(Decision 11 — a single-food object is a degenerate one-class mixture and
needs no segmenter or checkpoint, Req 3.1/3.2).

Per object: seat the mesh in a stable resting pose with its base on the
authored support plane, render the overhead z-depth at the pinned N5k
camera model (render.py, Decision 12), composite misses to the plane, and
stamp the object's shipped gramme weight as the single-class ground-truth
mass. True mesh volumes go to ``metafood3d_truth.json`` for the
volume-fit diagnostic (Req 2.3); the authored support-plane parameters go
to ``run_summary.json`` for the calibrate-side injected-plane branch
(Decision 13 — the fixture proto carries no support-plane field).

Metric scale (Req 1.5, Decision 14) — both gates abort BEFORE any fixture
is emitted, recording the failure in ``run_summary.json``:

- global unit-sanity: the snapshot's bbox max-extent median must sit in a
  physically sane millimetre band (catches a metre/centimetre import or
  loader-scale error once);
- per-object weight plausibility: the mesh bbox volume under a food
  density band must bracket the shipped gramme weight (an unchecked
  uniform scale error is a pure multiplicative volume error that would
  bake silently into β).

Expected gitignored local layout (``--mf3d-dir``; the dataset is
request-gated — https://lorenz.ecn.purdue.edu/~food3d/ — and licensed
CC BY-NC 4.0, never written into the repository, Req 1.2)::

    <mf3d-dir>/meshes/<category>/<object_id>.(obj|ply|glb|off)
    <mf3d-dir>/metadata.csv     # object_id, category, weight_g
                                # (derived from the shipped nutrition
                                # sheet when the snapshot lands)

Meshes are read in millimetres; if the real snapshot ships metre- or
centimetre-unit meshes the unit-sanity gate fails loudly and a documented
conversion belongs in the metadata derivation step, not in silence here.
Reconcile this layout (and regenerate the mapping artifact with
``build_mapping.py --categories-file``) on first contact with the real
snapshot.

Usage::

    tools/metafood3d/.venv/bin/python tools/metafood3d/ingest.py \\
        --mf3d-dir data/metafood3d --out build/mf3d_fixtures
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import struct
import sys
import zlib
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

_HERE = Path(__file__).resolve().parent
_REPO_ROOT = _HERE.parents[1]

DEFAULT_MF3D_DIR = _REPO_ROOT / "data" / "metafood3d"
DEFAULT_SCHEMA_DIR = (
    _REPO_ROOT / "MedataCore" / "Sources" / "PortableContracts" / "Schemas"
)

DATASET_NAME = "metafood3d"
LICENCE = "CC BY-NC 4.0"
SENTINEL_SHA = "no_segmenter"
ESTIMATOR_MIXTURE = "mixture"
PALETTE_VERSION = "v2"  # Decision 15
GRAVITY_NADIR = (0.0, 0.0, -1.0)

MESH_SUFFIXES = (".obj", ".ply", ".glb", ".off")

# ---- metric-scale gates (Req 1.5, Decision 14) ------------------------------ #
# (a) Global unit-sanity: median of the snapshot's bbox max extents. Real
# single-food objects sit in tens-to-hundreds of millimetres; a metre-unit
# import lands ~x1000 low, a centimetre one ~x10 low.
UNIT_SANITY_MEDIAN_EXTENT_BAND_MM = (20.0, 600.0)
# (b) Per-object weight plausibility: implied bbox density weight/V_bbox.
# Foods span roughly 0.1-1.5 g/cm3 and a mesh fills only part of its bbox,
# so the band is deliberately loose — it exists to catch scale errors, not
# to tighten nutrition physics.
WEIGHT_BBOX_DENSITY_BAND_G_PER_CM3 = (0.05, 2.0)

_SKIP_REASONS = (
    "missing_metadata", "malformed_weight", "malformed_mesh",
    "no_stable_pose", "render_miss",
)


def _import_sibling(name: str):
    """Unique-key sibling import (file names mirror tools/nutrition5k/, so
    plain ``import mapping`` would collide across tool test dirs)."""
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
render = _import_sibling("render")

# The pinned camera model (Req 2.4). RENDER_CONFIG is the runtime knob the
# tests shrink for speed; PINNED_RENDER_CONFIG documents the committed
# default and must stay the N5k-matched model.
PINNED_RENDER_CONFIG = render.DEFAULT_CONFIG
RENDER_CONFIG = PINNED_RENDER_CONFIG


def _import_make_fixtures():
    path = _REPO_ROOT / "tools" / "segmenter" / "make_fixtures.py"
    spec = importlib.util.spec_from_file_location(
        "metafood3d_make_fixtures", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _placeholder_png() -> bytes:
    """Deterministic 1x1 grey PNG. Mixture fixtures need a nadir_image but
    MetaFood3D emits no imagery (Req 1.2) and the mixture calibrate path
    never reads the pixels."""
    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return (struct.pack(">I", len(data)) + body
                + struct.pack(">I", zlib.crc32(body)))
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0)  # 1x1 8-bit grey
    idat = zlib.compress(b"\x00\x80", 9)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", idat) + chunk(b"IEND", b""))


PLACEHOLDER_PNG = _placeholder_png()


# --------------------------------------------------------------------------- #
# Metric-scale gates (pure; Hypothesis-tested).
# --------------------------------------------------------------------------- #
class ScaleError(Exception):
    """Metric-scale gate failure (Req 1.5). Carries the run-summary block
    so the abort is recorded before the process exits."""

    def __init__(self, message: str, summary: dict):
        super().__init__(message)
        self.summary = summary


@dataclass(frozen=True)
class ScaleCandidate:
    object_id: str
    bbox_extents_mm: tuple[float, float, float]
    weight_g: float


def check_metric_scale(candidates: list[ScaleCandidate]) -> None:
    """Both Decision 14 gates; raises ScaleError on the first failure."""
    if not candidates:
        return

    extents = [max(c.bbox_extents_mm) for c in candidates]
    median_extent = float(np.median(extents))
    lo, hi = UNIT_SANITY_MEDIAN_EXTENT_BAND_MM
    if not (lo <= median_extent <= hi):
        raise ScaleError(
            f"[ingest] unit-sanity gate failed: median bbox max extent "
            f"{median_extent:.3f} mm is outside [{lo:.0f}, {hi:.0f}] mm — "
            f"a millimetre/metre unit or loader-scale error must fail "
            f"loudly, not bake into beta (Req 1.5 / Decision 14).",
            summary={
                "gate": "unit_sanity",
                "median_bbox_max_extent_mm": median_extent,
                "expected_band_mm": [lo, hi],
            })

    rho_lo, rho_hi = WEIGHT_BBOX_DENSITY_BAND_G_PER_CM3
    for c in candidates:
        ex, ey, ez = c.bbox_extents_mm
        bbox_cm3 = (ex * ey * ez) / 1000.0
        if bbox_cm3 <= 0:
            raise ScaleError(
                f"[ingest] degenerate bbox for {c.object_id}",
                summary={"gate": "weight_plausibility",
                         "object_id": c.object_id,
                         "bbox_volume_cm3": bbox_cm3})
        implied = c.weight_g / bbox_cm3
        if not (rho_lo <= implied <= rho_hi):
            raise ScaleError(
                f"[ingest] weight-plausibility gate failed for "
                f"{c.object_id}: {c.weight_g:.1f} g over a "
                f"{bbox_cm3:.1f} cm3 bbox implies {implied:.4f} g/cm3, "
                f"outside [{rho_lo}, {rho_hi}] (Req 1.5 / Decision 14).",
                summary={
                    "gate": "weight_plausibility",
                    "object_id": c.object_id,
                    "weight_g": c.weight_g,
                    "bbox_volume_cm3": bbox_cm3,
                    "implied_density_g_per_cm3": implied,
                    "expected_band_g_per_cm3": [rho_lo, rho_hi],
                })


# --------------------------------------------------------------------------- #
# Dataset loading.
# --------------------------------------------------------------------------- #
@dataclass(frozen=True)
class ObjectRecord:
    object_id: str
    category: str          # normalised
    weight_g: float
    mesh_path: Path


def verify_required_files(mf3d_dir: Path) -> None:
    if not mf3d_dir.is_dir():
        raise SystemExit(
            f"[ingest] MetaFood3D directory not found: {mf3d_dir} — "
            f"expected the gitignored layout documented in this module's "
            f"docstring (the dataset is request-gated; see "
            f"https://lorenz.ecn.purdue.edu/~food3d/)."
        )
    missing = [rel for rel in ("meshes", "metadata.csv")
               if not (mf3d_dir / rel).exists()]
    if missing:
        raise SystemExit(
            f"[ingest] MetaFood3D directory {mf3d_dir} is missing "
            f"required entr(ies): {', '.join(missing)}"
        )


def load_metadata(mf3d_dir: Path) -> tuple[dict[str, tuple[str, float]], set[str]]:
    """metadata.csv rows: object_id -> (normalised category, weight_g);
    plus the malformed-weight object ids."""
    rows: dict[str, tuple[str, float]] = {}
    malformed: set[str] = set()
    with open(mf3d_dir / "metadata.csv", newline="") as fh:
        for row in csv.DictReader(fh):
            object_id = (row.get("object_id") or "").strip()
            if not object_id:
                continue
            category = mapping.normalise_category(row.get("category") or "")
            try:
                weight = float(row.get("weight_g") or "")
                if not np.isfinite(weight) or weight <= 0:
                    raise ValueError
            except ValueError:
                malformed.add(object_id)
                continue
            rows[object_id] = (category, weight)
    return rows, malformed


def discover_meshes(mf3d_dir: Path) -> list[Path]:
    return sorted(
        p for p in (mf3d_dir / "meshes").rglob("*")
        if p.is_file() and p.suffix.lower() in MESH_SUFFIXES)


def snapshot_identifier(mf3d_dir: Path, mesh_paths: list[Path]) -> str:
    """Operational dataset snapshot id (Req 9.1): SHA-256 over the
    metadata bytes plus the sorted mesh manifest (path + size)."""
    h = hashlib.sha256((mf3d_dir / "metadata.csv").read_bytes())
    for p in mesh_paths:
        h.update(f"{p.relative_to(mf3d_dir).as_posix()}:{p.stat().st_size}\n"
                 .encode())
    return h.hexdigest()


# --------------------------------------------------------------------------- #
# Seating (design §render table: stable resting pose, base on the plane).
# --------------------------------------------------------------------------- #
def seat_mesh(mesh, cfg) -> object:
    """Pose the mesh resting under gravity with its base ON the authored
    plane and body towards the camera (every food pixel nearer than the
    plane => positive height-above-plane; nothing dies in max(0, .)).

    Returns the posed copy, or None when no stable pose exists (recorded
    as a skip, design §Error Handling)."""
    posed = mesh.copy()
    try:
        transforms, _probs = posed.compute_stable_poses()
    except BaseException:
        return None
    if len(transforms) == 0:
        return None
    # Most probable resting pose: mesh rests on the z=0 plane, body in +z.
    posed.apply_transform(transforms[0])
    # Camera frame has +z pointing away from the camera (depth axis), so
    # flip "up" onto the -z direction by rotating pi about x, then seat
    # the base at the plane depth, centred on the optical axis.
    posed.apply_transform(np.array([
        [1.0, 0.0, 0.0, 0.0],
        [0.0, -1.0, 0.0, 0.0],
        [0.0, 0.0, -1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]))
    lo, hi = posed.bounds
    posed.apply_translation([
        -(lo[0] + hi[0]) / 2.0,
        -(lo[1] + hi[1]) / 2.0,
        cfg.plane_depth_mm - hi[2],
    ])
    return posed


# --------------------------------------------------------------------------- #
# Run.
# --------------------------------------------------------------------------- #
@dataclass
class RunSummary:
    ingested: int = 0
    skipped: dict[str, list[str]] = field(
        default_factory=lambda: {r: [] for r in _SKIP_REASONS})
    unmapped_excluded: dict[str, list[str]] = field(default_factory=dict)
    ambiguous_excluded: dict[str, list[str]] = field(default_factory=dict)


def _summary_doc(summary: RunSummary, *, source_dataset: str,
                 snapshot_id: str, categories_source: str,
                 cfg, scale_check_failed) -> dict:
    return {
        "dataset": DATASET_NAME,
        "licence": LICENCE,
        "source_dataset": source_dataset,
        "snapshot_identifier": snapshot_id,
        "mapping_categories_source": categories_source,
        "ingested": summary.ingested,
        "estimator_paths": {ESTIMATOR_MIXTURE: summary.ingested},
        "skipped": summary.skipped,
        "unmapped_excluded": summary.unmapped_excluded,
        "unmapped_excluded_count": sum(
            len(v) for v in summary.unmapped_excluded.values()),
        "ambiguous_excluded": summary.ambiguous_excluded,
        "ambiguous_excluded_count": sum(
            len(v) for v in summary.ambiguous_excluded.values()),
        # Req 2.4/2.5/9.1: the recorded camera configuration, including the
        # noise-free-render note (Decision 8).
        "render_config": cfg.as_lineage(),
        # Decision 13: the calibrate branch injects this authored plane
        # into TotalHullVolume instead of RANSAC-refitting it. The fixture
        # proto has no support-plane field, so it rides the run summary.
        "authored_support_plane": {
            "plane_depth_mm": cfg.plane_depth_mm,
            "normal_camera": [0.0, 0.0, 1.0],
            "convention": (
                "nadir camera frame, camera looks along -z (Math.proto); "
                "depth values are +z-depth mm, so the plane is the "
                "constant-depth surface at plane_depth_mm with its normal "
                "towards the camera"),
        },
        "thresholds": {
            "unit_sanity_median_extent_band_mm":
                list(UNIT_SANITY_MEDIAN_EXTENT_BAND_MM),
            "weight_bbox_density_band_g_per_cm3":
                list(WEIGHT_BBOX_DENSITY_BAND_G_PER_CM3),
        },
        "scale_check_failed": scale_check_failed,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mf3d-dir", default=str(DEFAULT_MF3D_DIR),
                        help="MetaFood3D data root (module docstring "
                             "layout; gitignored, Req 1.2).")
    parser.add_argument("--out", required=True,
                        help="Output directory for <object_id>.fixture, "
                             "run_summary.json and metafood3d_truth.json — "
                             "must be OUTSIDE the repository (Req 1.2).")
    parser.add_argument("--mapping", default=str(mapping.DEFAULT_ARTIFACT),
                        help="Mapping artifact (Req 1.3).")
    parser.add_argument("--schema-dir", default=str(DEFAULT_SCHEMA_DIR))
    parser.add_argument("--limit", type=int, default=None,
                        help="Ingest at most N objects (smoke runs).")
    args = parser.parse_args(argv)

    out_dir = Path(args.out).resolve()
    if out_dir.is_relative_to(_REPO_ROOT):
        raise SystemExit(
            f"[ingest] --out {out_dir} is inside the repo checkout "
            f"{_REPO_ROOT} — MetaFood3D-derived artifacts never land in "
            f"the repository (Req 1.2)."
        )

    mf3d_dir = Path(args.mf3d_dir)
    verify_required_files(mf3d_dir)

    palette = mapping.parse_palette()
    try:
        category_mapping = mapping.load_mapping(
            Path(args.mapping),
            expected_palette_class_list=palette.class_list,
        )
    except mapping.MappingError as exc:
        raise SystemExit(f"[ingest] {exc}")

    metadata, malformed_weight = load_metadata(mf3d_dir)
    mesh_paths = discover_meshes(mf3d_dir)
    if args.limit is not None:
        mesh_paths = mesh_paths[:args.limit]

    snapshot_id = snapshot_identifier(mf3d_dir, mesh_paths)
    source_dataset = f"{DATASET_NAME}@{snapshot_id[:12]}"
    cfg = RENDER_CONFIG

    import trimesh  # lazy: --help works without the venv

    summary = RunSummary()
    out_dir.mkdir(parents=True, exist_ok=True)

    # Pass 1 — load every object and gate the snapshot's metric scale
    # BEFORE emitting anything (Req 1.5).
    loaded: list[tuple[ObjectRecord, object]] = []
    candidates: list[ScaleCandidate] = []
    for mesh_path in mesh_paths:
        object_id = mesh_path.stem
        if object_id in malformed_weight:
            summary.skipped["malformed_weight"].append(object_id)
            continue
        meta = metadata.get(object_id)
        if meta is None:
            summary.skipped["missing_metadata"].append(object_id)
            continue
        category, weight_g = meta
        try:
            mesh = trimesh.load(mesh_path, force="mesh")
            extents = tuple(float(e) for e in mesh.extents)
            if len(mesh.faces) == 0 or not all(np.isfinite(extents)):
                raise ValueError("degenerate mesh")
        except BaseException:
            summary.skipped["malformed_mesh"].append(object_id)
            continue
        record = ObjectRecord(object_id=object_id, category=category,
                              weight_g=weight_g, mesh_path=mesh_path)
        loaded.append((record, mesh))
        candidates.append(ScaleCandidate(object_id, extents, weight_g))

    try:
        check_metric_scale(candidates)
    except ScaleError as exc:
        doc = _summary_doc(
            summary, source_dataset=source_dataset, snapshot_id=snapshot_id,
            categories_source=category_mapping.categories_source,
            cfg=cfg, scale_check_failed=exc.summary)
        (out_dir / "run_summary.json").write_text(
            json.dumps(doc, indent=2) + "\n")
        raise SystemExit(str(exc))

    mf = _import_make_fixtures()
    schema_dir = Path(args.schema_dir)
    truth: dict[str, float] = {}

    # Pass 2 — map, seat, render, emit.
    for record, mesh in loaded:
        entry = category_mapping.entries.get(record.category)
        status = entry.status if entry else mapping.STATUS_UNMAPPED
        if status == mapping.STATUS_AMBIGUOUS:
            summary.ambiguous_excluded.setdefault(
                record.category, []).append(record.object_id)
            continue
        if status != mapping.STATUS_MAPPED:
            # Unknown-to-the-artifact categories land here too (Req 1.4).
            summary.unmapped_excluded.setdefault(
                record.category, []).append(record.object_id)
            continue
        class_id = entry.class_id

        posed = seat_mesh(mesh, cfg)
        if posed is None:
            summary.skipped["no_stable_pose"].append(record.object_id)
            continue
        depth = render.render_overhead_depth(posed, cfg)
        if not (depth > 0).any():
            summary.skipped["render_miss"].append(record.object_id)
            continue
        composite = render.composite_support_plane(depth, cfg)

        data = mf.build_fixture_bytes(
            fixture_id=record.object_id,
            probs_hwc=None,
            argmax_hw=None,
            nadir_image_png=PLACEHOLDER_PNG,
            checkpoint_sha256=SENTINEL_SHA,
            schema_dir=schema_dir,
            palette_version=PALETTE_VERSION,
            depth_mm_hw=composite,
            intrinsics=(cfg.fx, cfg.fy, cfg.cx, cfg.cy,
                        cfg.width, cfg.height),
            gravity=GRAVITY_NADIR,
            ground_truth_class_mass_g={class_id: record.weight_g},
            source_dataset=source_dataset,
            estimator_path=ESTIMATOR_MIXTURE,
        )
        (out_dir / f"{record.object_id}.fixture").write_bytes(data)
        # True mesh volume for the non-baked volume-fit diagnostic
        # (Req 2.3); poses are rigid, so the source mesh volume is used.
        truth[record.object_id] = float(abs(mesh.volume))
        summary.ingested += 1

    doc = _summary_doc(
        summary, source_dataset=source_dataset, snapshot_id=snapshot_id,
        categories_source=category_mapping.categories_source,
        cfg=cfg, scale_check_failed=False)
    (out_dir / "run_summary.json").write_text(
        json.dumps(doc, indent=2) + "\n")
    (out_dir / "metafood3d_truth.json").write_text(
        json.dumps(truth, indent=2, sort_keys=True) + "\n")

    skipped_total = sum(len(v) for v in summary.skipped.values())
    print(f"[ingest] ingested {summary.ingested} objects "
          f"({skipped_total} skipped, "
          f"{doc['unmapped_excluded_count']} unmapped, "
          f"{doc['ambiguous_excluded_count']} ambiguous) -> {out_dir}")
    print(f"[ingest] snapshot {source_dataset}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

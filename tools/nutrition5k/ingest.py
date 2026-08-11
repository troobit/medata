#!/usr/bin/env python3
"""Bridge Nutrition5k overhead RGB-D into MeData ``.fixture`` files (Req 1/3).

Mirrors ``tools/segmenter/make_fixtures.py`` and reuses its
``build_fixture_bytes`` (extended for the nutrition5k proto fields) so the
proto-writing path stays a single pure function. Pre-checkpoint (no
``--checkpoint``), every plate is emitted as exactly one **mixture** fixture:
``estimator_path = "mixture"``, ``segmenter_checkpoint_sha256 =
"no_segmenter"``, and NO probability tensor (Req 3.7, Decision 17).

Depth: N5k raw depth is 16-bit in units of 10^-4 m (10,000 units/metre), so
``mm = raw / 10.0`` written as Float32 LE. Sentinel 0 (invalid return) and
pixels at/beyond the 0.4 m saturation cap are written as 0 so the estimator's
``zt > 0`` guard excludes them (Req 3.1/3.2). The run verifies the conversion
against two documented reference depths before emitting anything and aborts
when either falls outside its band — a 10x unit error must fail loudly.

Usage::

    python tools/nutrition5k/ingest.py --n5k-dir data --out build/n5k_fixtures

``--n5k-dir`` defaults to the gitignored ``data/`` layout documented in
specs/estimation/nutrition5k-calibration/prerequisites.md:
``data/n5k/realsense_overhead/dish_<id>/{rgb.png, depth_raw.png}``,
``data/metadata/*.csv``, ``data/dish_ids/splits/*.txt``. N5k imagery and
metadata are never written into the repository (Req 1.1).

Checkpoint mode (``--checkpoint``, Req 3.7 / 4.7): the liquid check runs
first — a plate whose liquid-mapped mass fraction is >= 0.05 is always
stamped mixture. Then a plate whose dominant mapped solid class reaches
tau_route = 0.90 of TOTAL plate mass (unmapped included) is stamped
``single_dominant``: the trained segmenter runs over its RGB via
``export.load_checkpoint`` / ``export.reference_input`` (make_fixtures.py
parity) and the probabilities + real checkpoint SHA are embedded. Everything
else stays mixture with the sentinel.

Regeneration semantics (Decision 17 / Req 5.2): when the model-production
Bucket C checkpoint lands, re-run ingestion WITH ``--checkpoint`` to
regenerate the FULL fixture set; ``HarnessCLI calibrate`` then re-fits both
paths and ``CalibrationMerge`` applies the Req 5.2 supersession (a qualifying
single-dominant β supersedes a previously baked mixture β, recorded in
lineage).
"""

from __future__ import annotations

import argparse
import csv
import datetime
import hashlib
import importlib.util
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))

import mapping  # noqa: E402

_REPO_ROOT = _HERE.parents[1]
DEFAULT_N5K_DIR = _REPO_ROOT / "data"
DEFAULT_SCHEMA_DIR = (
    _REPO_ROOT / "MedataCore" / "Sources" / "PortableContracts" / "Schemas"
)

# ---- depth conversion (Req 3.1/3.2) ---------------------------------------- #
DEPTH_UNITS_PER_MM = 10.0
# 0.4 m saturation cap at 10,000 units/metre: at/beyond-cap pixels carry no
# surface information and are excluded via 0 (Req 3.2).
DEPTH_CAP_RAW = 4000

# ---- documented reference depths (Req 3.1) --------------------------------- #
# Both strictly below the 0.4 m cap, where clamping cannot mask a scale error.
# The bands are deliberately wide: they exist to catch order-of-magnitude
# unit errors (raw/1000 or raw-as-mm land far outside both), not to tighten
# the nominal geometry. Both references are quantiles of the converted
# frames themselves — N5k publishes no independently surveyed rig distances.
# 1. Camera-to-plate: the fixed N5k rig places the plate surface ~350-400 mm
#    below the overhead RealSense (empirically: per-plate median of valid
#    converted depth); the band's low edge leaves room for tall dishes that
#    pull the median up towards the camera.
CAMERA_TO_PLATE_BAND_MM = (250.0, 400.0)
# 2. Food-top feature: the nearest food surface (1st percentile of valid
#    depth) must still be a plausible camera distance — no closer than
#    ~150 mm (roughly 250 mm of food height on the plate) and below the cap.
FOOD_TOP_BAND_MM = (150.0, 400.0)
# Reference verification runs over the first N convertible plates.
REFERENCE_SAMPLE_SIZE = 25

# ---- pinned nominal intrinsics (Req 3.3/3.4) -------------------------------- #
# N5k publishes no per-capture RealSense calibration (verified against the
# bucket + repo, prerequisites.md). One documented nominal model for every
# plate: RealSense D435 RGB-module factory intrinsics at the captured
# 640x480 (4:3), depth assumed registered to RGB. The systematic volume-scale
# risk folds into the Req 9.3 population-transfer caveat.
PINNED_INTRINSICS = (617.0, 617.0, 319.5, 239.5, 640, 480)

# Nadir camera looks straight down along -Z (Math.proto: right-handed,
# camera looks along -Z), so gravity in the nadir frame is -Z (Req 3.6).
GRAVITY_NADIR = (0.0, 0.0, -1.0)

# ---- routing thresholds (design §Provisional gate values) ------------------ #
TAU_ROUTE = 0.90                     # dominant mapped mass fraction (Req 3.7)
LIQUID_SIGNIFICANT_FRACTION = 0.05   # liquid-mapped mass fraction (Req 4.7)
UNMAPPED_SIGNIFICANT_FRACTION = 0.10  # mixture-fit admission (Req 4.1)

SENTINEL_SHA = "no_segmenter"
ESTIMATOR_MIXTURE = "mixture"
ESTIMATOR_SINGLE_DOMINANT = "single_dominant"
# Fixtures are stamped with the palette the parse targets
# (n5k-mapping-artifact-stale-v1-palette): the stamp must always equal the
# palette the tensors were emitted against, or the harness size guards reject
# in the harness against tensors sized for 36.
PALETTE_VERSION = "v0"

# Required files under --n5k-dir (Req 1.2/1.3; prerequisites.md layout).
_METADATA_FILES = (
    "metadata/dish_metadata_cafe1.csv",
    "metadata/dish_metadata_cafe2.csv",
    "metadata/ingredients_metadata.csv",
)
_SPLIT_FILES = (
    "dish_ids/splits/depth_train_ids.txt",
    "dish_ids/splits/depth_test_ids.txt",
    "dish_ids/splits/rgb_train_ids.txt",
    "dish_ids/splits/rgb_test_ids.txt",
)
_OVERHEAD_DIR = "n5k/realsense_overhead"

_SKIP_REASONS = (
    "missing_metadata", "malformed_mass", "missing_rgb", "missing_depth",
    "malformed_rgb", "malformed_depth", "resolution_mismatch",
    "depth_out_of_band",
)


def _import_make_fixtures():
    path = _REPO_ROOT / "tools" / "segmenter" / "make_fixtures.py"
    spec = importlib.util.spec_from_file_location("segmenter_make_fixtures", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def _import_pil():
    try:
        from PIL import Image
        return Image
    except ImportError as exc:
        raise SystemExit(
            "Pillow is required. Install with:\n  pip install Pillow"
        ) from exc


def _import_export_module():
    """Import tools/segmenter/export.py to reuse load_checkpoint +
    reference_input — segmenter parity with make_fixtures.py (Req 5.1)."""
    path = _REPO_ROOT / "tools" / "segmenter" / "export.py"
    if not path.is_file():
        raise SystemExit(f"expected segmenter export module at {path}")
    spec = importlib.util.spec_from_file_location("segmenter_export", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


# Segmenter input size — must match export.reference_input / make_fixtures.
SEGMENTER_TARGET_SIZE = 513


def _load_segmenter(checkpoint_path: str, num_classes: int):
    """Lazy (torch-importing) checkpoint load. Monkeypatchable seam."""
    export = _import_export_module()
    return export.load_checkpoint(num_classes, checkpoint_path)


def _run_segmenter(model, rgb_path: str, num_classes: int) -> np.ndarray:
    """Softmax probabilities [H, W, C] float32 at SEGMENTER_TARGET_SIZE, via
    the exact ImageNet transform export/make_fixtures use. Monkeypatchable
    seam."""
    export = _import_export_module()
    torch, _ = export._import_torch()
    x = export.reference_input(SEGMENTER_TARGET_SIZE, rgb_path)  # [1,3,H,W]
    with torch.no_grad():
        out = model(torch.from_numpy(x))
        logits = out["out"] if isinstance(out, dict) else out
        probs = torch.softmax(logits, dim=1)[0]  # [C, H, W]
    probs_chw = probs.cpu().numpy().astype(np.float32)
    if probs_chw.shape[0] != num_classes:
        raise SystemExit(
            f"[ingest] segmenter produced {probs_chw.shape[0]} classes, "
            f"expected {num_classes}"
        )
    return np.transpose(probs_chw, (1, 2, 0))


# --------------------------------------------------------------------------- #
# Pure helpers.
# --------------------------------------------------------------------------- #
def convert_depth_raw_to_mm(raw: np.ndarray) -> np.ndarray:
    """Raw N5k depth (uint16, 10^-4 m units) -> Float32 millimetres.

    Sentinel 0 and at/beyond-cap pixels become 0.0 so the estimator's
    ``zt > 0`` guard excludes them (Req 3.2)."""
    raw = np.asarray(raw)
    mm = raw.astype(np.float32) / np.float32(DEPTH_UNITS_PER_MM)
    mm[(raw == 0) | (raw >= DEPTH_CAP_RAW)] = 0.0
    return mm


def depth_reference_stats(mm: np.ndarray) -> tuple[float, float] | None:
    """(camera-to-plate, food-top) reference depths of one converted frame:
    median and 1st percentile of the valid (> 0) pixels."""
    valid = mm[mm > 0.0]
    if valid.size == 0:
        return None
    return float(np.median(valid)), float(np.percentile(valid, 1))


def _in_band(value: float, band: tuple[float, float]) -> bool:
    return band[0] <= value < band[1]


@dataclass(frozen=True)
class DishRecord:
    dish_id: str
    total_carbs_g: float
    total_protein_g: float
    total_fat_g: float
    # (ingredient_id, name, grams, carbs_g, protein_g, fat_g) per ingredient
    # row — the macro columns are the N5k per-ingredient absolute values that
    # feed the fixture's per-class GT macro maps (Req 6.2/6.6).
    ingredients: list[tuple[str, str, float, float, float, float]]


@dataclass(frozen=True)
class RouteInfo:
    """Mass-fraction view of one plate against the mapping artifact."""
    mapped_mass_g: dict[str, float]      # class_id -> grams (solids + liquids)
    total_mass_g: float
    liquid_fraction: float               # liquid-mapped mass / total
    unmapped_fraction: float             # unmapped + ambiguous mass / total
    dominant_class: str | None           # dominant mapped SOLID class
    dominant_fraction: float             # its fraction of TOTAL plate mass


def route_info(record: DishRecord, plate_mapping: mapping.Mapping,
               palette: mapping.PaletteClasses) -> RouteInfo:
    liquid_set = set(palette.liquid)
    mapped: dict[str, float] = {}
    liquid_mass = 0.0
    unmapped_mass = 0.0
    total = 0.0
    for ingredient_id, _name, grams, *_macros in record.ingredients:
        total += grams
        class_id = plate_mapping.class_for(ingredient_id)
        if class_id is None:
            unmapped_mass += grams
            continue
        mapped[class_id] = mapped.get(class_id, 0.0) + grams
        if class_id in liquid_set:
            liquid_mass += grams

    solid_classes = {c: g for c, g in mapped.items() if c not in liquid_set}
    dominant_class = max(solid_classes, key=solid_classes.get, default=None)
    dominant_fraction = (
        solid_classes[dominant_class] / total if dominant_class and total > 0
        else 0.0
    )
    return RouteInfo(
        mapped_mass_g=mapped,
        total_mass_g=total,
        liquid_fraction=liquid_mass / total if total > 0 else 0.0,
        unmapped_fraction=unmapped_mass / total if total > 0 else 0.0,
        dominant_class=dominant_class,
        dominant_fraction=dominant_fraction,
    )


def class_macros(
    record: DishRecord, plate_mapping: mapping.Mapping,
) -> tuple[dict[str, float], dict[str, float], dict[str, float]]:
    """Per-class GT macro sums (carbs, protein, fat) over MAPPED ingredients
    (Req 6.2/6.6). These are N5k's own per-ingredient values — the eval's GT
    basis, deliberately not re-derivable from the DB composition, so the
    Req 6.7 cross-macro check can see composition-source errors."""
    carbs: dict[str, float] = {}
    protein: dict[str, float] = {}
    fat: dict[str, float] = {}
    for ingredient_id, _name, _grams, carbs_g, protein_g, fat_g \
            in record.ingredients:
        class_id = plate_mapping.class_for(ingredient_id)
        if class_id is None:
            continue
        carbs[class_id] = carbs.get(class_id, 0.0) + carbs_g
        protein[class_id] = protein.get(class_id, 0.0) + protein_g
        fat[class_id] = fat.get(class_id, 0.0) + fat_g
    return carbs, protein, fat


def decide_estimator_path(info: RouteInfo, *, checkpoint_available: bool) -> str:
    """Authoritative estimator_path stamp (Req 3.7 / 4.7 routing).

    Liquid check FIRST: a plate whose liquid-mapped mass fraction reaches the
    significant fraction is always mixture, never single_dominant. Then the
    dominant mapped solid class's fraction of TOTAL plate mass (unmapped
    included — an unmapped-heavy plate cannot be stamped single-dominant)
    must clear tau_route."""
    if not checkpoint_available:
        return ESTIMATOR_MIXTURE
    if info.liquid_fraction >= LIQUID_SIGNIFICANT_FRACTION:
        return ESTIMATOR_MIXTURE
    if (info.dominant_class is not None
            and info.dominant_fraction >= TAU_ROUTE):
        return ESTIMATOR_SINGLE_DOMINANT
    return ESTIMATOR_MIXTURE


# --------------------------------------------------------------------------- #
# Metadata + manifest.
# --------------------------------------------------------------------------- #
def load_dish_metadata(n5k_dir: Path) -> tuple[dict[str, DishRecord], set[str]]:
    """Parse both cafe CSVs. Returns (records, malformed dish ids).

    Row layout: dish_id, total_cal, total_mass, total_fat, total_carb,
    total_protein, then per-ingredient (id, name, grams, cal, fat, carb,
    protein) groups."""
    records: dict[str, DishRecord] = {}
    malformed: set[str] = set()
    for name in ("dish_metadata_cafe1.csv", "dish_metadata_cafe2.csv"):
        with open(n5k_dir / "metadata" / name, newline="") as fh:
            for row in csv.reader(fh):
                if not row or not row[0].strip():
                    continue
                dish_id = row[0].strip()
                if dish_id in records or dish_id in malformed:
                    continue
                try:
                    _cal, total_mass, fat, carb, protein = (
                        float(v) for v in row[1:6]
                    )
                    ingredients = []
                    for i in range(6, len(row) - 6, 7):
                        # Per-ingredient group: id, name, grams, cal, fat,
                        # carb, protein (absolute values for the portion).
                        grams = float(row[i + 2])
                        ing_fat = float(row[i + 4])
                        ing_carb = float(row[i + 5])
                        ing_protein = float(row[i + 6])
                        ingredients.append((row[i].strip(), row[i + 1].strip(),
                                            grams, ing_carb, ing_protein,
                                            ing_fat))
                    if not ingredients:
                        raise ValueError("no ingredients")
                    plate_mass = sum(t[2] for t in ingredients)
                    if (not np.isfinite(total_mass) or plate_mass <= 0
                            or any(not np.isfinite(g) or g < 0
                                   for _, _, g, *_ in ingredients)
                            or any(not np.isfinite(m)
                                   for t in ingredients for m in t[3:])):
                        raise ValueError("non-finite mass or macro")
                except (ValueError, IndexError):
                    malformed.add(dish_id)
                    continue
                records[dish_id] = DishRecord(
                    dish_id=dish_id,
                    total_carbs_g=carb,
                    total_protein_g=protein,
                    total_fat_g=fat,
                    ingredients=ingredients,
                )
    return records, malformed


def release_identifier(n5k_dir: Path) -> str:
    """SHA-256 manifest of the fetched metadata + split files (Req 1.4 —
    the GCS bucket is unversioned, so this is the operational release id)."""
    lines = []
    for relative in sorted(_METADATA_FILES + _SPLIT_FILES):
        digest = hashlib.sha256((n5k_dir / relative).read_bytes()).hexdigest()
        lines.append(f"{relative}:{digest}")
    return hashlib.sha256("\n".join(lines).encode()).hexdigest()


# --------------------------------------------------------------------------- #
# Image loading.
# --------------------------------------------------------------------------- #
class _PlateError(Exception):
    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


def _load_depth_raw(dish_dir: Path) -> np.ndarray:
    Image = _import_pil()
    path = dish_dir / "depth_raw.png"
    if not path.is_file():
        raise _PlateError("missing_depth")
    try:
        arr = np.asarray(Image.open(path))
    except Exception:
        raise _PlateError("malformed_depth")
    if arr.dtype != np.uint16 or arr.ndim != 2:
        raise _PlateError("malformed_depth")
    return arr


def _load_rgb(dish_dir: Path) -> tuple[bytes, tuple[int, int]]:
    Image = _import_pil()
    path = dish_dir / "rgb.png"
    if not path.is_file():
        raise _PlateError("missing_rgb")
    try:
        with Image.open(path) as img:
            size = img.size
            img.load()
    except Exception:
        raise _PlateError("malformed_rgb")
    return path.read_bytes(), size


# --------------------------------------------------------------------------- #
# Run.
# --------------------------------------------------------------------------- #
@dataclass
class RunSummary:
    ingested: int = 0
    skipped: dict[str, list[str]] = field(
        default_factory=lambda: {r: [] for r in _SKIP_REASONS})
    estimator_paths: dict[str, int] = field(
        default_factory=lambda: {ESTIMATOR_MIXTURE: 0,
                                 ESTIMATOR_SINGLE_DOMINANT: 0})
    mixture_fit_excluded_unmapped: list[str] = field(default_factory=list)
    liquid_excluded: list[str] = field(default_factory=list)


def verify_required_files(n5k_dir: Path) -> None:
    if not n5k_dir.is_dir():
        raise SystemExit(
            f"[ingest] N5k directory not found: {n5k_dir} — expected the "
            f"layout documented in specs/estimation/nutrition5k-calibration/"
            f"prerequisites.md (fetch from gs://nutrition5k_dataset)."
        )
    missing = []
    overhead = n5k_dir / _OVERHEAD_DIR
    if not overhead.is_dir():
        missing.append(_OVERHEAD_DIR + "/")
    for relative in _METADATA_FILES + _SPLIT_FILES:
        if not (n5k_dir / relative).is_file():
            missing.append(relative)
    if missing:
        raise SystemExit(
            f"[ingest] N5k directory {n5k_dir} is missing required "
            f"artifact(s): {', '.join(missing)} (Req 1.2; layout per "
            f"prerequisites.md)."
        )


def _verify_reference_depths(dish_dirs: list[Path]) -> None:
    """Req 3.1: verify the raw->mm conversion against the two documented
    reference depths over a leading sample; abort before emitting anything."""
    plate_refs: list[float] = []
    food_refs: list[float] = []
    for dish_dir in dish_dirs:
        if len(plate_refs) >= REFERENCE_SAMPLE_SIZE:
            break
        try:
            raw = _load_depth_raw(dish_dir)
        except _PlateError:
            continue
        stats = depth_reference_stats(convert_depth_raw_to_mm(raw))
        if stats is None:
            continue
        plate_refs.append(stats[0])
        food_refs.append(stats[1])
    if not plate_refs:
        return  # nothing convertible; every plate will be skipped+recorded

    plate_mm = float(np.median(plate_refs))
    food_mm = float(np.median(food_refs))
    for label, value, band in (
        ("camera-to-plate median", plate_mm, CAMERA_TO_PLATE_BAND_MM),
        ("food-top 1st-percentile", food_mm, FOOD_TOP_BAND_MM),
    ):
        if not _in_band(value, band):
            raise SystemExit(
                f"[ingest] reference depth check failed: {label} = "
                f"{value:.1f} mm is outside the documented band "
                f"[{band[0]:.0f}, {band[1]:.0f}) mm (Req 3.1 — check the "
                f"raw/{DEPTH_UNITS_PER_MM:.0f} unit conversion; a 10x unit "
                f"error must fail loudly, not bake)."
            )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--n5k-dir", default=str(DEFAULT_N5K_DIR),
                        help="N5k data root (prerequisites.md layout).")
    parser.add_argument("--out", required=True,
                        help="Output directory for <dish_id>.fixture files "
                             "and run_summary.json (outside the repo; "
                             "Req 1.1).")
    parser.add_argument("--mapping", default=str(mapping.DEFAULT_ARTIFACT),
                        help="Mapping artifact (Req 2).")
    parser.add_argument("--schema-dir", default=str(DEFAULT_SCHEMA_DIR))
    parser.add_argument("--download-date", default=None,
                        help="ISO date the dataset was fetched (Req 1.4); "
                             "defaults to the metadata CSV's mtime date.")
    parser.add_argument("--limit", type=int, default=None,
                        help="Ingest at most N dishes (smoke runs).")
    parser.add_argument("--checkpoint", default=None,
                        help="Trained segmenter checkpoint (.pt). Enables "
                             "single_dominant routing (Req 3.7); without it "
                             "every plate is a mixture fixture.")
    args = parser.parse_args(argv)

    n5k_dir = Path(args.n5k_dir)
    verify_required_files(n5k_dir)

    checkpoint = Path(args.checkpoint) if args.checkpoint else None
    if checkpoint is not None and not checkpoint.is_file():
        raise SystemExit(f"[ingest] --checkpoint not found: {checkpoint}")

    ingredients_csv = n5k_dir / "metadata" / "ingredients_metadata.csv"
    palette = mapping.parse_palette()
    try:
        plate_mapping = mapping.load_mapping(
            Path(args.mapping),
            expected_palette_class_list=palette.class_list,
            expected_metadata_version=mapping.metadata_version(ingredients_csv),
        )
    except mapping.MappingError as exc:
        raise SystemExit(f"[ingest] {exc}")

    download_date = args.download_date or datetime.date.fromtimestamp(
        ingredients_csv.stat().st_mtime).isoformat()
    release_id = release_identifier(n5k_dir)
    metadata_version = plate_mapping.n5k_metadata_version
    source_dataset = f"nutrition5k@{release_id[:12]}/{metadata_version[:12]}"

    records, malformed_mass = load_dish_metadata(n5k_dir)
    dish_dirs = sorted(
        d for d in (n5k_dir / _OVERHEAD_DIR).iterdir() if d.is_dir())
    if args.limit is not None:
        dish_dirs = dish_dirs[:args.limit]

    _verify_reference_depths(dish_dirs)

    mf = _import_make_fixtures()
    schema_dir = Path(args.schema_dir)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Checkpoint mode: total classes = palette content + 3 sentinels
    # (background / unknown_food / unsupported_liquid).
    num_classes = len(palette.class_list) + 3
    model = None
    checkpoint_sha = None
    if checkpoint is not None:
        checkpoint_sha = hashlib.sha256(checkpoint.read_bytes()).hexdigest()
        print(f"[ingest] checkpoint SHA-256 = {checkpoint_sha}")
        model = _load_segmenter(str(checkpoint), num_classes)

    summary = RunSummary()
    _fx, _fy, _cx, _cy, pin_w, pin_h = PINNED_INTRINSICS

    for dish_dir in dish_dirs:
        dish_id = dish_dir.name
        try:
            if dish_id in malformed_mass:
                raise _PlateError("malformed_mass")
            record = records.get(dish_id)
            if record is None:
                raise _PlateError("missing_metadata")

            rgb_bytes, rgb_size = _load_rgb(dish_dir)
            raw = _load_depth_raw(dish_dir)
            # Req 3.4 — dimensional registration check against the single
            # pinned model; no per-plate ad-hoc intrinsics.
            if (rgb_size != (pin_w, pin_h)
                    or raw.shape != (pin_h, pin_w)):
                raise _PlateError("resolution_mismatch")

            depth_mm = convert_depth_raw_to_mm(raw)
            stats = depth_reference_stats(depth_mm)
            if stats is None:
                raise _PlateError("malformed_depth")
            if (not _in_band(stats[0], CAMERA_TO_PLATE_BAND_MM)
                    or not _in_band(stats[1], FOOD_TOP_BAND_MM)):
                raise _PlateError("depth_out_of_band")
        except _PlateError as exc:
            summary.skipped[exc.reason].append(dish_id)
            continue

        info = route_info(record, plate_mapping, palette)
        if info.total_mass_g <= 0:
            summary.skipped["malformed_mass"].append(dish_id)
            continue
        if info.liquid_fraction >= LIQUID_SIGNIFICANT_FRACTION:
            summary.liquid_excluded.append(dish_id)
        elif info.unmapped_fraction > UNMAPPED_SIGNIFICANT_FRACTION:
            summary.mixture_fit_excluded_unmapped.append(dish_id)

        estimator_path = decide_estimator_path(
            info, checkpoint_available=model is not None)
        probs = None
        sha = SENTINEL_SHA
        if estimator_path == ESTIMATOR_SINGLE_DOMINANT:
            # Real probabilities + real checkpoint SHA (Req 3.7); N5k has no
            # ground-truth mask, so nadir_argmax stays empty and the tau_purity
            # gate derives the argmax from these probs in the harness.
            probs = _run_segmenter(model, str(dish_dir / "rgb.png"),
                                   num_classes)
            sha = checkpoint_sha
        gt_carbs, gt_protein, gt_fat = class_macros(record, plate_mapping)
        data = mf.build_fixture_bytes(
            fixture_id=dish_id,
            probs_hwc=probs,
            argmax_hw=None,
            nadir_image_png=rgb_bytes,
            checkpoint_sha256=sha,
            schema_dir=schema_dir,
            palette_version=PALETTE_VERSION,
            depth_mm_hw=depth_mm,
            intrinsics=PINNED_INTRINSICS,
            gravity=GRAVITY_NADIR,
            ground_truth_class_mass_g=info.mapped_mass_g,
            ground_truth_total_carbs_g=record.total_carbs_g,
            ground_truth_protein_g=record.total_protein_g,
            ground_truth_fat_g=record.total_fat_g,
            ground_truth_class_carbs_g=gt_carbs,
            ground_truth_class_protein_g=gt_protein,
            ground_truth_class_fat_g=gt_fat,
            source_dataset=source_dataset,
            estimator_path=estimator_path,
        )
        (out_dir / f"{dish_id}.fixture").write_bytes(data)
        summary.ingested += 1
        summary.estimator_paths[estimator_path] += 1

    summary_doc = {
        "ingested": summary.ingested,
        "skipped": summary.skipped,
        "estimator_paths": summary.estimator_paths,
        "mixture_fit_excluded_unmapped": summary.mixture_fit_excluded_unmapped,
        "liquid_excluded": summary.liquid_excluded,
        "release_identifier": release_id,
        "download_date": download_date,
        "n5k_metadata_version": metadata_version,
        "source_dataset": source_dataset,
        "pinned_intrinsics": {
            "model": "RealSense D435 RGB-module factory nominal, 640x480",
            "fx": PINNED_INTRINSICS[0], "fy": PINNED_INTRINSICS[1],
            "cx": PINNED_INTRINSICS[2], "cy": PINNED_INTRINSICS[3],
        },
        "thresholds": {
            "tau_route": TAU_ROUTE,
            "liquid_significant_fraction": LIQUID_SIGNIFICANT_FRACTION,
            "unmapped_significant_fraction": UNMAPPED_SIGNIFICANT_FRACTION,
            "depth_cap_raw": DEPTH_CAP_RAW,
            "camera_to_plate_band_mm": list(CAMERA_TO_PLATE_BAND_MM),
            "food_top_band_mm": list(FOOD_TOP_BAND_MM),
        },
    }
    (out_dir / "run_summary.json").write_text(
        json.dumps(summary_doc, indent=2) + "\n")

    skipped_total = sum(len(v) for v in summary.skipped.values())
    print(f"[ingest] ingested {summary.ingested} plates "
          f"({skipped_total} skipped) -> {out_dir}")
    print(f"[ingest] release {source_dataset}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

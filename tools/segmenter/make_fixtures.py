#!/usr/bin/env python3
"""Build seg-bench fixtures from the trained segmenter (ML pipeline step 5a).

`HarnessCLI seg-bench` does **not** run the model. It reads ``.fixture`` files
(serialised ``PbMealFixture`` protos) that already carry the model's FP16
probability tensor plus a ground-truth argmax mask, stamped with the
checkpoint's SHA-256. This script produces those fixtures: it runs the trained
checkpoint over the held-out split and writes one ``<id>.fixture`` per image.

Semantic contract (mirrors HarnessCLI/main.swift runSegBench):
  - ``nadir_probs``   = the MODEL's prediction. FP16 IEEE-754 binary16 LE,
                        layout [H, W, C] row-major (HWC), C = num_classes,
                        top-left origin. seg-bench derives the PREDICTED argmax
                        from this tensor.
  - ``nadir_argmax``  = the GROUND-TRUTH remapped mask. UInt8 [H, W] row-major,
                        values in [0, C). seg-bench treats this as truth.
  - ``nadir_intrinsics`` carries image_width = W, image_height = H — seg-bench
                        reads W and H from the intrinsics, so they MUST match the
                        tensor dimensions. Focal length / principal point are set
                        to sane positive values (unused by seg-bench).
  - ``segmenter_checkpoint_sha256`` = SHA-256 hex of the checkpoint ``.pt`` file.
                        FixtureLoader refuses fixtures whose SHA does not match
                        the ``--checkpoint-sha256`` seg-bench is invoked with.

Usage (step 5a)::

    python tools/segmenter/make_fixtures.py \\
        --checkpoint tools/segmenter/build/checkpoint.pt \\
        --heldout data/foodseg103_remapped/heldout \\
        --out tests/fixtures/segmenter/heldout

It also writes the export reference image (ml-training §6) used by
``export.py`` to prove Core ML / TFLite agreement — derived from the first
held-out image, or a deterministic synthetic plate if none is available::

    --reference-out tests/fixtures/segmenter/reference.png

The held-out split is the directory ``prepare_dataset.py`` writes:
``<heldout>/images/<stem>.{png,jpg,jpeg}`` paired with
``<heldout>/masks/<stem>.png`` (single-channel UInt8 class IDs already remapped
to the v1 palette per §3b). As a fallback, a flat directory whose masks sit
beside the images as ``<stem>_mask.png`` / ``<stem>.mask.png`` / ``<stem>_gt.png``
is also accepted. Images with no matching mask are skipped with a warning.

Design note: the proto-writing path (numpy arrays → ``.fixture`` bytes) is a
pure function (``build_fixture_bytes``) deliberately decoupled from the torch
inference path, so it is smoke-testable without PyTorch installed.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

# Special-class layout of the redefined v1 palette: 24 solid + 8 liquid
# classes + background + unknown_food + unsupported_liquid = 35 (mirrors
# ClassPalette.v1Standard, totalClasses = foodClasses.count +
# liquidClasses.count + 3; Decisions 23/24).
DEFAULT_NUM_CLASSES = 35
DEFAULT_TARGET_SIZE = 513

# ImageNet normalisation — MUST match export.reference_input so the probs we
# write here are produced by the same transform the export equivalence check
# (and on-device pre-processor) assume.
_IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
_IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)

_IMAGE_EXTS = (".png", ".jpg", ".jpeg")
_MASK_SUFFIXES = ("_mask.png", ".mask.png", "_gt.png")

_HERE = Path(__file__).resolve().parent
_DEFAULT_SCHEMA_DIR = (
    _HERE.parents[1] / "MedataCore" / "Sources" / "PortableContracts" / "Schemas"
)
_PROTO_FILES = (
    "MealFixture.proto",
    "CameraIntrinsics.proto",
    "DepthMap.proto",
    "Math.proto",
)


# --------------------------------------------------------------------------- #
# Lazy imports (keep --help and the pure proto path working without torch).
# --------------------------------------------------------------------------- #
def _import_pil():
    try:
        from PIL import Image
        return Image
    except ImportError as exc:
        raise SystemExit(
            "Pillow is required. Install with:\n  pip install Pillow"
        ) from exc


def _import_export_module():
    """Import the sibling export.py to reuse load_checkpoint + reference_input,
    so inference here matches training/export exactly."""
    export_path = _HERE / "export.py"
    if not export_path.is_file():
        raise SystemExit(f"expected sibling export.py at {export_path}")
    spec = importlib.util.spec_from_file_location("segmenter_export", export_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def _import_meal_fixture_pb(schema_dir: Path):
    """Compile MealFixture.proto (+ imports) with protoc into a temp dir and
    import the generated MealFixture_pb2 module. Caches across calls per dir."""
    cache_key = str(schema_dir.resolve())
    cached = _import_meal_fixture_pb._cache.get(cache_key)
    if cached is not None:
        return cached

    try:
        import google.protobuf  # noqa: F401
    except ImportError as exc:
        raise SystemExit(
            "The 'protobuf' Python runtime is required to import generated "
            "bindings. Install with:\n"
            "  uv pip install --system protobuf\n"
            "  (or: pip install protobuf)"
        ) from exc

    if not schema_dir.is_dir():
        raise SystemExit(f"--schema-dir not found: {schema_dir}")
    for proto in _PROTO_FILES:
        if not (schema_dir / proto).is_file():
            raise SystemExit(f"missing proto {proto} in {schema_dir}")

    out_dir = Path(tempfile.mkdtemp(prefix="medata_pb_"))
    cmd = [
        "protoc",
        f"-I{schema_dir}",
        f"--python_out={out_dir}",
        *_PROTO_FILES,
    ]
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
    except FileNotFoundError as exc:
        raise SystemExit(
            "protoc not found on PATH. Install with:\n"
            "  brew install protobuf"
        ) from exc
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"protoc failed:\n{exc.stderr}") from exc

    sys.path.insert(0, str(out_dir))
    try:
        import MealFixture_pb2  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            f"failed to import generated MealFixture_pb2 from {out_dir}: {exc}"
        ) from exc

    _import_meal_fixture_pb._cache[cache_key] = MealFixture_pb2
    return MealFixture_pb2


_import_meal_fixture_pb._cache = {}  # type: ignore[attr-defined]


# --------------------------------------------------------------------------- #
# Pure helpers (no torch).
# --------------------------------------------------------------------------- #
def sha256_of_file(path: str | Path) -> str:
    """SHA-256 hex of a file's bytes (matches `shasum -a 256`)."""
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def png_bytes(rgb_uint8: np.ndarray) -> bytes:
    """Encode an [H, W, 3] uint8 RGB array as PNG bytes (sRGB, top-left origin)."""
    Image = _import_pil()
    if rgb_uint8.dtype != np.uint8 or rgb_uint8.ndim != 3 or rgb_uint8.shape[2] != 3:
        raise ValueError("png_bytes expects an [H, W, 3] uint8 RGB array")
    buf = io.BytesIO()
    Image.fromarray(rgb_uint8, mode="RGB").save(buf, format="PNG")
    return buf.getvalue()


def build_fixture_bytes(
    *,
    fixture_id: str,
    probs_hwc: np.ndarray | None,
    argmax_hw: np.ndarray | None,
    nadir_image_png: bytes,
    checkpoint_sha256: str,
    schema_dir: Path,
    fixture_revision: str = "rev-1",
    palette_version: str = "v1",
    database_edition: str = "CoFID 2024 + IFCDB 2023",
    capture_path_canonical: str = "single_view_lidar",
    depth_mm_hw: np.ndarray | None = None,
    intrinsics: tuple[float, float, float, float, int, int] | None = None,
    gravity: tuple[float, float, float] | None = None,
    ground_truth_class_mass_g: dict[str, float] | None = None,
    ground_truth_total_carbs_g: float | None = None,
    ground_truth_protein_g: float | None = None,
    ground_truth_fat_g: float | None = None,
    source_dataset: str | None = None,
    estimator_path: str | None = None,
) -> bytes:
    """Serialise a single PbMealFixture from numpy arrays. Pure (no torch).

    ``probs_hwc``  : float array [H, W, C] — stored as FP16 LE, HWC row-major.
                     None for mixture fixtures, which must NOT carry
                     segmentation probabilities (nutrition5k Req 3.7).
    ``argmax_hw``  : uint8 array [H, W]     — stored as UInt8 row-major.
                     None when there is no ground-truth mask (N5k plates).
    ``depth_mm_hw``: float32 array [H, W]   — DepthMap.depth_bytes_mm,
                     Float32 LE millimetres, 0 = excluded pixel (Req 3.2).
    ``intrinsics`` : (fx, fy, cx, cy, width, height) override. Required when
                     ``probs_hwc`` is None (there is no tensor to derive the
                     seg-bench W/H from).
    Returns the serialised proto bytes (write these to ``<id>.fixture``).
    """
    if probs_hwc is not None and probs_hwc.ndim != 3:
        raise ValueError(f"probs must be [H, W, C]; got shape {probs_hwc.shape}")
    if argmax_hw is not None and argmax_hw.ndim != 2:
        raise ValueError(f"argmax must be [H, W]; got shape {argmax_hw.shape}")
    if probs_hwc is not None and argmax_hw is not None:
        h, w, _ = probs_hwc.shape
        if argmax_hw.shape != (h, w):
            raise ValueError(
                f"argmax shape {argmax_hw.shape} != probs spatial dims {(h, w)}"
            )
    if probs_hwc is None and intrinsics is None:
        raise ValueError("intrinsics are required when probs_hwc is None")

    pb = _import_meal_fixture_pb(schema_dir)
    fx = pb.MealFixture()
    fx.fixture_id = fixture_id
    fx.fixture_revision = fixture_revision
    fx.palette_version = palette_version
    fx.database_edition = database_edition
    fx.segmenter_checkpoint_sha256 = checkpoint_sha256
    fx.nadir_image = nadir_image_png
    fx.capture_path_canonical = capture_path_canonical

    if probs_hwc is not None:
        # FP16 LE, contiguous HWC row-major. astype('<f2') forces little-endian.
        probs_fp16 = np.ascontiguousarray(probs_hwc, dtype=np.float32).astype("<f2")
        fx.nadir_probs = probs_fp16.tobytes(order="C")

    if argmax_hw is not None:
        argmax = np.ascontiguousarray(argmax_hw, dtype=np.uint8)
        fx.nadir_argmax = argmax.tobytes(order="C")

    if intrinsics is not None:
        k_fx, k_fy, k_cx, k_cy, k_w, k_h = intrinsics
        fx.nadir_intrinsics.fx = float(k_fx)
        fx.nadir_intrinsics.fy = float(k_fy)
        fx.nadir_intrinsics.cx = float(k_cx)
        fx.nadir_intrinsics.cy = float(k_cy)
        fx.nadir_intrinsics.image_width = int(k_w)
        fx.nadir_intrinsics.image_height = int(k_h)
    else:
        # seg-bench reads W, H from the intrinsics; focal/principal are unused
        # there but set to sane positive values.
        h, w, _ = probs_hwc.shape
        fx.nadir_intrinsics.image_width = w
        fx.nadir_intrinsics.image_height = h
        fx.nadir_intrinsics.fx = float(w)
        fx.nadir_intrinsics.fy = float(w)
        fx.nadir_intrinsics.cx = float(w) / 2.0
        fx.nadir_intrinsics.cy = float(h) / 2.0

    if depth_mm_hw is not None:
        if depth_mm_hw.ndim != 2:
            raise ValueError(
                f"depth must be [H, W]; got shape {depth_mm_hw.shape}"
            )
        depth = np.ascontiguousarray(depth_mm_hw).astype("<f4")
        fx.nadir_depth.depth_bytes_mm = depth.tobytes(order="C")
        fx.nadir_depth.height, fx.nadir_depth.width = depth.shape
        fx.nadir_depth.row_stride_bytes = depth.shape[1] * 4
        fx.nadir_depth.depth_intrinsics.CopyFrom(fx.nadir_intrinsics)
        # Depth supplied this way is already registered to the RGB frame
        # (N5k publishes registered overhead depth; the assumption is recorded
        # in lineage), so depth_from_colour is an explicit identity — the
        # Swift DepthMap bridge requires exactly 16 floats and fails loudly
        # on an empty matrix.
        del fx.nadir_depth.depth_from_colour.m[:]
        fx.nadir_depth.depth_from_colour.m.extend(
            1.0 if i % 5 == 0 else 0.0 for i in range(16))

    if gravity is not None:
        fx.gravity.x, fx.gravity.y, fx.gravity.z = (float(v) for v in gravity)

    for class_id, grams in (ground_truth_class_mass_g or {}).items():
        fx.ground_truth_class_mass_g[class_id] = float(grams)
    if ground_truth_total_carbs_g is not None:
        fx.ground_truth_total_carbs_g = float(ground_truth_total_carbs_g)
    if ground_truth_protein_g is not None:
        fx.ground_truth_protein_g = float(ground_truth_protein_g)
    if ground_truth_fat_g is not None:
        fx.ground_truth_fat_g = float(ground_truth_fat_g)
    if source_dataset is not None:
        fx.source_dataset = source_dataset
    if estimator_path is not None:
        fx.estimator_path = estimator_path

    return fx.SerializeToString()


def synthetic_plate(target_size: int) -> np.ndarray:
    """Deterministic [H, W, 3] uint8 RGB plate-ish image for when no held-out
    image exists (a centred warm disc on a neutral background)."""
    n = target_size
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    cy = cx = (n - 1) / 2.0
    r = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2)
    disc = r < (n * 0.35)
    img = np.full((n, n, 3), 200, dtype=np.uint8)  # neutral plate
    img[disc] = (196, 132, 84)  # warm food tone
    return img


# --------------------------------------------------------------------------- #
# Held-out split discovery.
# --------------------------------------------------------------------------- #
def find_mask_for(image_path: Path) -> Path | None:
    stem = image_path.stem
    for suffix in _MASK_SUFFIXES:
        cand = image_path.with_name(stem + suffix)
        if cand.is_file():
            return cand
    return None


def list_heldout_pairs(heldout_dir: Path) -> list[tuple[Path, Path]]:
    """Return (image, mask) pairs found in the held-out directory, sorted by name.

    Primary layout is what ``prepare_dataset.py`` writes: ``images/<stem>.*`` +
    ``masks/<stem>.png`` (separate subdirs, matching stem). Falls back to a flat
    directory where masks sit beside images as ``<stem>_mask.png`` etc.
    """
    img_dir = heldout_dir / "images"
    mask_dir = heldout_dir / "masks"
    pairs: list[tuple[Path, Path]] = []

    if img_dir.is_dir() and mask_dir.is_dir():
        # prepare_dataset.py layout: pair by stem across the two subdirs.
        for path in sorted(img_dir.iterdir()):
            if path.suffix.lower() not in _IMAGE_EXTS:
                continue
            mask = mask_dir / (path.stem + ".png")
            if not mask.is_file():
                print(f"[make-fixtures] no mask for {path.name}; skipping",
                      file=sys.stderr)
                continue
            pairs.append((path, mask))
        return pairs

    # Fallback: flat directory with sibling <stem>_mask.png masks.
    for path in sorted(heldout_dir.iterdir()):
        if path.suffix.lower() not in _IMAGE_EXTS:
            continue
        if any(path.name.endswith(s) for s in _MASK_SUFFIXES):
            continue
        mask = find_mask_for(path)
        if mask is None:
            print(f"[make-fixtures] no mask for {path.name}; skipping", file=sys.stderr)
            continue
        pairs.append((path, mask))
    return pairs


# --------------------------------------------------------------------------- #
# Inference (torch — lazy).
# --------------------------------------------------------------------------- #
def run_model_probs(model, x_chw: np.ndarray, num_classes: int) -> np.ndarray:
    """Run the model on a single [1, 3, H, W] FP32 input and return softmax
    probabilities as [H, W, C] float32 (HWC)."""
    export = run_model_probs._export
    torch, _ = export._import_torch()
    with torch.no_grad():
        out = model(torch.from_numpy(x_chw))
        logits = out["out"] if isinstance(out, dict) else out  # [1, C, H, W]
        probs = torch.softmax(logits, dim=1)[0]  # [C, H, W]
    probs_chw = probs.cpu().numpy().astype(np.float32)
    if probs_chw.shape[0] != num_classes:
        raise SystemExit(
            f"model produced {probs_chw.shape[0]} classes, expected {num_classes}"
        )
    return np.transpose(probs_chw, (1, 2, 0))  # HWC


run_model_probs._export = None  # type: ignore[attr-defined]


def load_mask(mask_path: Path, target_size: int, num_classes: int) -> np.ndarray:
    """Load a class-id mask, nearest-resize to target_size, clamp to [0, C)."""
    Image = _import_pil()
    mask = Image.open(mask_path)
    if mask.mode not in ("L", "P", "I"):
        mask = mask.convert("L")
    mask = mask.resize((target_size, target_size), Image.NEAREST)
    arr = np.asarray(mask, dtype=np.int64)
    if arr.max(initial=0) >= num_classes:
        print(
            f"[make-fixtures] mask {mask_path.name} has ids >= {num_classes}; "
            "clamping (check §3b remapping)",
            file=sys.stderr,
        )
        arr = np.clip(arr, 0, num_classes - 1)
    return arr.astype(np.uint8)


# --------------------------------------------------------------------------- #
# Main.
# --------------------------------------------------------------------------- #
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--checkpoint", required=True,
                        help="Path to the trained .pt checkpoint (its SHA-256 is "
                             "stamped into every fixture).")
    parser.add_argument("--heldout", required=True,
                        help="Directory of held-out image/mask pairs.")
    parser.add_argument("--out", required=True,
                        help="Output directory for <id>.fixture files.")
    parser.add_argument("--reference-out",
                        default="tests/fixtures/segmenter/reference.png",
                        help="Where to write the export reference PNG (§6).")
    parser.add_argument("--num-classes", type=int, default=DEFAULT_NUM_CLASSES)
    parser.add_argument("--target-size", type=int, default=DEFAULT_TARGET_SIZE)
    parser.add_argument("--schema-dir", default=str(_DEFAULT_SCHEMA_DIR),
                        help="Directory containing the .proto schemas.")
    args = parser.parse_args(argv)

    schema_dir = Path(args.schema_dir)
    checkpoint = Path(args.checkpoint)
    if not checkpoint.is_file():
        raise SystemExit(f"--checkpoint not found: {checkpoint}")
    heldout = Path(args.heldout)
    if not heldout.is_dir():
        raise SystemExit(f"--heldout not found: {heldout}")

    sha = sha256_of_file(checkpoint)
    print(f"[make-fixtures] checkpoint SHA-256 = {sha}")

    pairs = list_heldout_pairs(heldout)
    if not pairs:
        raise SystemExit(f"no image/mask pairs found in {heldout}")
    print(f"[make-fixtures] {len(pairs)} held-out pairs")

    # Reuse export.py for model construction + the exact ImageNet transform.
    export = _import_export_module()
    run_model_probs._export = export
    model = export.load_checkpoint(args.num_classes, str(checkpoint))

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    Image = _import_pil()

    reference_written = False
    for image_path, mask_path in pairs:
        fixture_id = image_path.stem
        # Normalised input via export.reference_input → exact train/export parity.
        x = export.reference_input(args.target_size, str(image_path))  # [1,3,H,W]
        probs_hwc = run_model_probs(model, x, args.num_classes)
        argmax_hw = load_mask(mask_path, args.target_size, args.num_classes)

        rgb = (
            np.asarray(
                Image.open(image_path).convert("RGB").resize(
                    (args.target_size, args.target_size)
                ),
                dtype=np.uint8,
            )
        )
        data = build_fixture_bytes(
            fixture_id=fixture_id,
            probs_hwc=probs_hwc,
            argmax_hw=argmax_hw,
            nadir_image_png=png_bytes(rgb),
            checkpoint_sha256=sha,
            schema_dir=schema_dir,
        )
        (out_dir / f"{fixture_id}.fixture").write_bytes(data)
        print(f"[make-fixtures] wrote {fixture_id}.fixture ({len(data)} bytes)")

        if not reference_written:
            ref_out = Path(args.reference_out)
            ref_out.parent.mkdir(parents=True, exist_ok=True)
            ref_out.write_bytes(png_bytes(rgb))
            print(f"[make-fixtures] reference image → {ref_out}")
            reference_written = True

    if not reference_written:
        ref_out = Path(args.reference_out)
        ref_out.parent.mkdir(parents=True, exist_ok=True)
        ref_out.write_bytes(png_bytes(synthetic_plate(args.target_size)))
        print(f"[make-fixtures] synthetic reference image → {ref_out}")

    print("[make-fixtures] done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

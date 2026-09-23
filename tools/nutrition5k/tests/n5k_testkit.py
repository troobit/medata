"""Shared synthetic-N5k helpers for the nutrition5k tool tests."""

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import mapping  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]

# Synthetic N5k ingredient rows used by the tree builder: (numeric_id, name,
# cal/g, fat/g, carb/g, protein/g) — mirrors ingredients_metadata.csv columns.
SYNTH_INGREDIENTS = [
    (26, "white rice", 1.300, 0.003, 0.280, 0.027),
    (27, "broccoli", 0.350, 0.004, 0.070, 0.024),
    (326, "chicken soup", 0.360, 0.012, 0.040, 0.025),
    (508, "soy sauce", 0.530, 0.006, 0.049, 0.081),
]


def write_depth_png(path: Path, depth_raw: np.ndarray) -> None:
    from PIL import Image

    assert depth_raw.dtype == np.uint16
    Image.fromarray(depth_raw).save(path)


def write_rgb_png(path: Path, width: int = 640, height: int = 480) -> None:
    from PIL import Image

    rgb = np.full((height, width, 3), 180, dtype=np.uint8)
    Image.fromarray(rgb, mode="RGB").save(path)


def plate_depth(plate_raw: int = 3600, food_raw: int = 3400,
                table_raw: int = 4100, width: int = 640,
                height: int = 480) -> np.ndarray:
    """Plausible synthetic overhead capture: table beyond the 0.4 m cap,
    plate disc at ~360 mm, central food bump at ~340 mm."""
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    r = np.sqrt((yy - (height - 1) / 2) ** 2 + (xx - (width - 1) / 2) ** 2)
    depth = np.full((height, width), table_raw, dtype=np.uint16)
    depth[r < height * 0.4] = plate_raw
    depth[r < height * 0.15] = food_raw
    return depth


def make_n5k_tree(root: Path, dishes: dict) -> Path:
    """Write the documented data/ layout (prerequisites.md).

    ``dishes`` maps dish_id -> dict with optional keys:
      ingredients: list of (numeric_id, grams) against SYNTH_INGREDIENTS
      depth: uint16 array (default plate_depth())
      rgb_size: (width, height) of rgb.png
      skip_rgb / skip_depth / corrupt_depth / omit_metadata: fault injection
    """
    overhead = root / "n5k" / "realsense_overhead"
    metadata_dir = root / "metadata"
    splits = root / "dish_ids" / "splits"
    for d in (overhead, metadata_dir, splits):
        d.mkdir(parents=True, exist_ok=True)

    nutrition = {i[0]: i for i in SYNTH_INGREDIENTS}
    dish_rows = []
    for dish_id, cfg in dishes.items():
        dish_dir = overhead / dish_id
        dish_dir.mkdir(parents=True, exist_ok=True)
        if not cfg.get("skip_rgb"):
            w, h = cfg.get("rgb_size", (640, 480))
            write_rgb_png(dish_dir / "rgb.png", w, h)
        if cfg.get("corrupt_depth"):
            (dish_dir / "depth_raw.png").write_bytes(b"not a png")
        elif not cfg.get("skip_depth"):
            depth = cfg.get("depth")
            write_depth_png(dish_dir / "depth_raw.png",
                            depth if depth is not None else plate_depth())
        if cfg.get("omit_metadata"):
            continue

        totals = [0.0, 0.0, 0.0, 0.0, 0.0]  # cal, mass, fat, carb, protein
        cells = []
        for numeric_id, grams in cfg.get("ingredients", [(26, 150.0)]):
            _, name, cal, fat, carb, protein = nutrition[numeric_id]
            cells += [mapping.canonical_ingredient_id(numeric_id), name,
                      f"{grams}", f"{grams * cal}", f"{grams * fat}",
                      f"{grams * carb}", f"{grams * protein}"]
            totals[0] += grams * cal
            totals[1] += grams
            totals[2] += grams * fat
            totals[3] += grams * carb
            totals[4] += grams * protein
        dish_rows.append(",".join([dish_id] + [f"{t}" for t in totals] + cells))

    (metadata_dir / "dish_metadata_cafe1.csv").write_text(
        "\n".join(dish_rows) + ("\n" if dish_rows else ""))
    (metadata_dir / "dish_metadata_cafe2.csv").write_text("")
    (metadata_dir / "ingredients_metadata.csv").write_text(
        "ingr,id,cal/g,fat(g),carb(g),protein(g)\n" + "".join(
            f"{name},{nid},{cal},{fat},{carb},{protein}\n"
            for nid, name, cal, fat, carb, protein in SYNTH_INGREDIENTS))

    ids = sorted(dishes)
    (splits / "depth_train_ids.txt").write_text("\n".join(ids) + "\n")
    (splits / "depth_test_ids.txt").write_text("")
    (splits / "rgb_train_ids.txt").write_text("")
    (splits / "rgb_test_ids.txt").write_text("")
    return root


def make_test_mapping_artifact(path: Path, n5k_root: Path) -> Path:
    """Mapping artifact keyed to the synthetic ingredient CSV (Req 2.5) with
    the real palette content: white rice / broccoli mapped, chicken soup
    liquid-mapped, soy sauce unmapped."""
    palette = mapping.parse_palette()
    csv_path = n5k_root / "metadata" / "ingredients_metadata.csv"
    artifact = {
        "palette_class_list": palette.class_list,
        "n5k_metadata_version": mapping.metadata_version(csv_path),
        "mappings": [
            {"n5k_ingredient_id": "ingr_0000000026",
             "class_id": "white_rice", "status": "mapped"},
            {"n5k_ingredient_id": "ingr_0000000027",
             "class_id": "broccoli", "status": "mapped"},
            {"n5k_ingredient_id": "ingr_0000000326",
             "class_id": "soup", "status": "mapped"},
            {"n5k_ingredient_id": "ingr_0000000508",
             "class_id": None, "status": "unmapped"},
        ],
    }
    path.write_text(json.dumps(artifact))
    return path

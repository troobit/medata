"""Rasterise MyFoodRepo-273 COCO polygon annotations to v2-palette PNG masks.

Bridge step for the myfoodrepo-bridge PRD (dataset-bridge task 4): the AIcrowd
Food Recognition Benchmark ships instance segmentation as COCO polygons; the
training pipeline consumes semantic PNG masks in palette channel space (one
uint8 channel index per pixel, same format ``prepare_dataset.py`` emits for
FoodSeg103). This module flattens instances to semantics through the committed
``class_mapping_myfoodrepo273_v1.json`` (same schema as the FoodSeg103 mapping:
``mappings[].source_id -> target_index``, ``special_channels``,
``channel_count``).

Overlap rule (deterministic, documented per the task): annotations are painted
in order of polygon area DESCENDING, ties broken by annotation id ASCENDING —
so where two instances overlap, the smaller-area instance is painted later and
wins. Rationale: in food photography the smaller item overwhelmingly sits ON
the larger one (sauce on pasta, topping on rice); painting large-to-small keeps
the occluding item visible instead of burying it. Area is computed with the
shoelace formula over the annotation's own polygon parts — never the COCO
``area`` field — so the rule is a pure function of the geometry that is
actually painted.

Strictness:
- a ``category_id`` absent from the mapping is a hard error — task 3's mapping
  is total (unmapped source categories route to ``unknown_food`` THERE), so a
  miss here means mapping and annotations disagree;
- ``target_index: null`` (rule ``curated_drop``) paints background, mirroring
  ``prepare_dataset.py``;
- non-polygon segmentation (RLE) is a hard error naming the annotation id —
  MyFoodRepo-273 is polygon-only, and a silent skip would fake coverage.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, List, Optional, Sequence

import numpy as np
from PIL import Image, ImageDraw


def build_category_lut(mapping: dict) -> Dict[int, Optional[int]]:
    """source category_id -> target channel (None for curated_drop)."""
    if "mappings" not in mapping or "special_channels" not in mapping:
        raise ValueError(
            "mapping JSON is not a class-mapping artefact "
            "(missing 'mappings'/'special_channels')."
        )
    return {int(m["source_id"]): m["target_index"] for m in mapping["mappings"]}


def polygon_area(part: Sequence[float]) -> float:
    """Shoelace area of one flat [x1, y1, x2, y2, ...] polygon part."""
    xs = np.asarray(part[0::2], dtype=np.float64)
    ys = np.asarray(part[1::2], dtype=np.float64)
    return float(abs(np.dot(xs, np.roll(ys, -1)) - np.dot(ys, np.roll(xs, -1))) / 2.0)


def annotation_area(annotation: dict) -> float:
    segmentation = annotation["segmentation"]
    if not isinstance(segmentation, list):
        raise ValueError(
            f"annotation {annotation.get('id')}: non-polygon segmentation "
            "(RLE?) — MyFoodRepo-273 is polygon-only, refusing to skip silently."
        )
    return sum(polygon_area(part) for part in segmentation)


def rasterise_image(
    annotations: List[dict],
    height: int,
    width: int,
    category_lut: Dict[int, Optional[int]],
    background: int,
) -> np.ndarray:
    """Flatten one image's instance annotations to a semantic uint8 mask."""
    canvas = Image.new("L", (width, height), color=background)
    draw = ImageDraw.Draw(canvas)
    # Largest first, smaller instances painted later win overlaps; id breaks ties.
    ordered = sorted(annotations, key=lambda a: (-annotation_area(a), int(a["id"])))
    for annotation in ordered:
        category = int(annotation["category_id"])
        if category not in category_lut:
            raise ValueError(
                f"annotation {annotation.get('id')}: category_id {category} "
                "is not in the class mapping — mapping and annotations disagree."
            )
        target = category_lut[category]
        channel = background if target is None else int(target)
        for part in annotation["segmentation"]:
            points = list(zip(part[0::2], part[1::2]))
            if len(points) >= 3:
                draw.polygon(points, fill=channel)
    return np.asarray(canvas, dtype=np.uint8)


def rasterise_coco(
    coco: dict,
    category_lut: Dict[int, Optional[int]],
    background: int,
    out_dir: Path,
) -> dict:
    """Write one mask PNG per COCO image; return a summary index."""
    out_dir.mkdir(parents=True, exist_ok=True)
    by_image: Dict[int, List[dict]] = {}
    for annotation in coco["annotations"]:
        by_image.setdefault(int(annotation["image_id"]), []).append(annotation)

    index = {"masks": {}, "images_without_annotations": []}
    for image in coco["images"]:
        image_id = int(image["id"])
        stem = Path(image["file_name"]).stem
        annotations = by_image.get(image_id, [])
        if not annotations:
            # No annotations -> whole-background mask would teach the model the
            # food in the photo is background; record and skip instead.
            index["images_without_annotations"].append(stem)
            continue
        mask = rasterise_image(
            annotations, int(image["height"]), int(image["width"]),
            category_lut, background,
        )
        path = out_dir / f"{stem}.png"
        Image.fromarray(mask, mode="L").save(path)
        index["masks"][stem] = path.name
    return index


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Rasterise MyFoodRepo-273 COCO polygons to v2 semantic masks."
    )
    parser.add_argument("--annotations", required=True, type=Path,
                        help="COCO annotations.json")
    parser.add_argument("--mapping", required=True, type=Path,
                        help="class_mapping_myfoodrepo273_v1.json")
    parser.add_argument("--out", required=True, type=Path,
                        help="output directory for mask PNGs")
    args = parser.parse_args()

    mapping = json.loads(args.mapping.read_text())
    coco = json.loads(args.annotations.read_text())
    background = int(mapping["special_channels"]["background"])
    lut = build_category_lut(mapping)

    index = rasterise_coco(coco, lut, background, args.out)
    (args.out / "rasterise_index.json").write_text(
        json.dumps(index, indent=2, sort_keys=True) + "\n"
    )
    skipped = len(index["images_without_annotations"])
    print(f"[rasterise] wrote {len(index['masks'])} masks to {args.out}; "
          f"{skipped} images had no annotations (recorded, not rasterised)")


if __name__ == "__main__":
    main()

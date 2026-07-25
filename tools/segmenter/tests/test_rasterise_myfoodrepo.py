"""Torch-free tests for the MyFoodRepo-273 COCO polygon rasteriser
(myfoodrepo-bridge dataset-bridge task 4).

The real dataset is not required: synthetic COCO dicts drive the geometry, and
a minimal mapping fixture mirrors the class_mapping schema (source_id ->
target_index, special_channels at the v2 sentinels 33/34/35).
"""

import json

import numpy as np
import pytest
from PIL import Image

import rasterise_myfoodrepo as rmf

BACKGROUND = 33
UNKNOWN_FOOD = 34

MAPPING = {
    "mappings": [
        {"source_id": 1, "source_name": "rice", "target_index": 0},
        {"source_id": 2, "source_name": "chips", "target_index": 3},
        {"source_id": 3, "source_name": "doily", "target_index": None,
         "rule": "curated_drop"},
        {"source_id": 4, "source_name": "mystery", "target_index": UNKNOWN_FOOD},
    ],
    "special_channels": {"background": BACKGROUND, "unknown_food": UNKNOWN_FOOD,
                         "unsupported_liquid": 35},
}


def square(x0, y0, x1, y1):
    return [x0, y0, x1, y0, x1, y1, x0, y1]


def annotation(aid, category, parts):
    return {"id": aid, "category_id": category, "segmentation": parts}


@pytest.fixture()
def lut():
    return rmf.build_category_lut(MAPPING)


def test_single_polygon_paints_channel_and_background(lut):
    mask = rmf.rasterise_image(
        [annotation(1, 1, [square(2, 2, 7, 7)])], 10, 10, lut, BACKGROUND)
    assert mask[4, 4] == 0            # rice channel inside
    assert mask[0, 0] == BACKGROUND   # untouched pixels stay background
    assert mask.dtype == np.uint8
    assert mask.shape == (10, 10)


def test_smaller_area_wins_overlap(lut):
    big = annotation(1, 1, [square(0, 0, 9, 9)])
    small = annotation(2, 2, [square(3, 3, 6, 6)])
    # Order in the input list must not matter — the area rule decides.
    for annotations in ([big, small], [small, big]):
        mask = rmf.rasterise_image(annotations, 12, 12, lut, BACKGROUND)
        assert mask[4, 4] == 3   # chips (smaller) on top
        assert mask[1, 1] == 0   # rice elsewhere


def test_equal_area_tie_breaks_on_annotation_id(lut):
    first = annotation(1, 1, [square(0, 0, 5, 5)])
    second = annotation(2, 2, [square(0, 0, 5, 5)])
    mask = rmf.rasterise_image([second, first], 8, 8, lut, BACKGROUND)
    # Equal areas: lower id painted first, higher id overwrites.
    assert mask[2, 2] == 3


def test_curated_drop_paints_background(lut):
    mask = rmf.rasterise_image(
        [annotation(1, 3, [square(0, 0, 5, 5)])], 8, 8, lut, BACKGROUND)
    assert (mask == BACKGROUND).all()


def test_unmapped_category_is_a_hard_error(lut):
    with pytest.raises(ValueError, match="category_id 99"):
        rmf.rasterise_image(
            [annotation(7, 99, [square(0, 0, 3, 3)])], 5, 5, lut, BACKGROUND)


def test_rle_segmentation_is_a_hard_error(lut):
    rle = {"id": 9, "category_id": 1,
           "segmentation": {"counts": [0, 25], "size": [5, 5]}}
    with pytest.raises(ValueError, match="annotation 9"):
        rmf.rasterise_image([rle], 5, 5, lut, BACKGROUND)


def test_multi_part_polygon_paints_every_part(lut):
    parts = [square(0, 0, 3, 3), square(6, 6, 9, 9)]
    mask = rmf.rasterise_image(
        [annotation(1, 1, parts)], 12, 12, lut, BACKGROUND)
    assert mask[1, 1] == 0
    assert mask[7, 7] == 0
    assert mask[5, 5] == BACKGROUND


def test_shoelace_area_matches_rectangle():
    assert rmf.polygon_area(square(0, 0, 4, 3)) == pytest.approx(12.0)


def test_rasterise_coco_writes_masks_and_index(tmp_path, lut):
    coco = {
        "images": [
            {"id": 10, "file_name": "meal_010.jpg", "height": 8, "width": 8},
            {"id": 11, "file_name": "meal_011.jpg", "height": 8, "width": 8},
        ],
        "annotations": [
            {"id": 1, "image_id": 10, "category_id": 4,
             "segmentation": [square(1, 1, 6, 6)]},
        ],
    }
    index = rmf.rasterise_coco(coco, lut, BACKGROUND, tmp_path)
    assert index["masks"] == {"meal_010": "meal_010.png"}
    # An image with no annotations is recorded, never written as all-background.
    assert index["images_without_annotations"] == ["meal_011"]
    written = np.asarray(Image.open(tmp_path / "meal_010.png"))
    assert written[3, 3] == UNKNOWN_FOOD
    assert written[0, 0] == BACKGROUND
    assert not (tmp_path / "meal_011.png").exists()


def test_build_category_lut_rejects_non_mapping_json():
    with pytest.raises(ValueError, match="class-mapping"):
        rmf.build_category_lut({"schema": "something_else"})


def test_cli_round_trip(tmp_path):
    coco = {
        "images": [{"id": 1, "file_name": "a.jpg", "height": 6, "width": 6}],
        "annotations": [{"id": 1, "image_id": 1, "category_id": 2,
                         "segmentation": [square(0, 0, 5, 5)]}],
    }
    ann = tmp_path / "annotations.json"
    ann.write_text(json.dumps(coco))
    mapping = tmp_path / "mapping.json"
    mapping.write_text(json.dumps(MAPPING))
    out = tmp_path / "masks"

    import subprocess
    import sys
    from pathlib import Path
    script = Path(rmf.__file__)
    result = subprocess.run(
        [sys.executable, str(script), "--annotations", str(ann),
         "--mapping", str(mapping), "--out", str(out)],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr
    assert (out / "a.png").exists()
    index = json.loads((out / "rasterise_index.json").read_text())
    assert index["masks"] == {"a": "a.png"}

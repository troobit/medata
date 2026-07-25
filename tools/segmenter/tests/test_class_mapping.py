"""FoodSeg103 remap over the v2 palette (Req 7.2, Decisions 23/24, MD-29).

Palette v2 adds cereal as solid index 24, shifting the liquids to 25-32 and
the sentinels to background=33 / unknown_food=34 / unsupported_liquid=35.
parse_palette's assert moves to the new total, and the wine/coffee/tea/milk/
juice/soup FoodSeg103 categories route to the coarse liquid classes instead
of collapsing to unsupported_liquid. (FoodSeg103 has no beer category and no
cereal category; milkshake has no palette home and stays unsupported_liquid.)

The committed class_mapping_foodseg103_v1.json is palette-locked and must be
regenerated in the same change (Decision 23 consequence).
"""

import json
from pathlib import Path

import pytest

import build_class_mapping as bcm

REPO_ROOT = Path(__file__).resolve().parents[3]
GENERATE_PY = REPO_ROOT / "tools" / "food_db" / "generate.py"
COMMITTED_MAPPING = REPO_ROOT / "tools" / "segmenter" / "class_mapping_foodseg103_v1.json"

LIQUID_CLASSES = ["water", "coffee", "tea", "milk",
                  "fruit_juice", "soup", "beer", "wine"]
SOLID_COUNT = 25
TOTAL_CLASSES = SOLID_COUNT + len(LIQUID_CLASSES)

# FoodSeg103 category -> expected coarse liquid channel (liquids start at 25).
LIQUID_ROUTES = {
    "wine": SOLID_COUNT + LIQUID_CLASSES.index("wine"),
    "coffee": SOLID_COUNT + LIQUID_CLASSES.index("coffee"),
    "tea": SOLID_COUNT + LIQUID_CLASSES.index("tea"),
    "milk": SOLID_COUNT + LIQUID_CLASSES.index("milk"),
    "juice": SOLID_COUNT + LIQUID_CLASSES.index("fruit_juice"),
    "soup": SOLID_COUNT + LIQUID_CLASSES.index("soup"),
}


@pytest.fixture(scope="module")
def palette():
    return bcm.parse_palette(GENERATE_PY)


def test_parse_palette_reads_solid_plus_liquid(palette):
    assert len(palette) == TOTAL_CLASSES
    assert palette[SOLID_COUNT:] == LIQUID_CLASSES
    assert palette[0] == "white_rice"


def test_sentinel_channels_follow_the_liquids():
    assert bcm.BACKGROUND == TOTAL_CLASSES
    assert bcm.UNKNOWN_FOOD == TOTAL_CLASSES + 1
    assert bcm.UNSUPPORTED_LIQUID == TOTAL_CLASSES + 2


@pytest.mark.parametrize("foodseg_name,expected_index", LIQUID_ROUTES.items())
def test_liquid_categories_route_to_coarse_classes(palette, foodseg_name,
                                                   expected_index):
    index, name, rule = bcm.route(foodseg_name, palette)
    assert index == expected_index, (
        f"{foodseg_name} must route to the coarse liquid channel, "
        f"not unsupported_liquid"
    )
    assert rule == "curated_food"


def test_unhomed_liquid_stays_unsupported(palette):
    # milkshake has no palette class; it must NOT be forced into a coarse
    # class it isn't.
    index, name, _ = bcm.route("milkshake", palette)
    assert index == bcm.UNSUPPORTED_LIQUID
    assert name == "unsupported_liquid"


def test_committed_mapping_artifact_regenerated():
    # Decision 23 consequence: every palette-locked artifact regenerates in
    # the same change. The committed remap must reflect the 36-channel layout.
    mapping = json.loads(COMMITTED_MAPPING.read_text())
    assert mapping["channel_count"] == TOTAL_CLASSES + 3
    assert mapping["special_channels"] == {
        "background": TOTAL_CLASSES,
        "unknown_food": TOTAL_CLASSES + 1,
        "unsupported_liquid": TOTAL_CLASSES + 2,
    }
    by_name = {m["source_name"]: m for m in mapping["mappings"]}
    for foodseg_name, expected_index in LIQUID_ROUTES.items():
        assert by_name[foodseg_name]["target_index"] == expected_index
    assert by_name["milkshake"]["target_index"] == TOTAL_CLASSES + 2
    target_names = {t["name"] for t in mapping["target_channels"]}
    assert set(LIQUID_CLASSES) <= target_names

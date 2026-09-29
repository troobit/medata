"""Food Recognition 2022 remap over the palette (myfoodrepo-bridge
dataset-bridge task 3, MD-30 substitution).

Torch-free and dataset-free: routing tests drive ``route_2022`` with names
directly; artefact tests read the COMMITTED ``class_mapping_foodrec2022.json``
(regenerating it needs the dataset's annotations.json, which lives only in the
main checkout's gitignored ``data/`` tree).
"""

import json
from pathlib import Path

import pytest

import build_class_mapping as bcm
import build_class_mapping_foodrec2022 as b22

REPO_ROOT = Path(__file__).resolve().parents[3]
GENERATE_PY = REPO_ROOT / "tools" / "food_db" / "generate.py"
COMMITTED_MAPPING = (REPO_ROOT / "tools" / "segmenter"
                     / "class_mapping_foodrec2022.json")

TOTAL_CLASSES = 33
CHANNEL_COUNT = 36


@pytest.fixture(scope="module")
def palette():
    return bcm.parse_palette(GENERATE_PY)


# ── routing rules ───────────────────────────────────────────────────────────

@pytest.mark.parametrize("source,target", [
    # the four classes this bridge exists for
    ("porridge-prepared-with-partially-skimmed-milk", "cereal"),
    ("muesli", "cereal"),
    ("corn-flakes", "cereal"),
    ("rice-whole-grain", "brown_rice"),
    ("bread-wholemeal", "bread_wholemeal"),
    ("bread-whole-wheat", "bread_wholemeal"),
    ("mashed-potatoes-prepared-with-full-fat-milk-with-butter", "potato_mashed"),
    # staple spot-checks
    ("rice", "white_rice"),
    ("pasta-spaghetti", "pasta"),
    ("bread-white", "bread_white"),
    ("potatoes-steamed", "potato_boiled"),
    ("chips-french-fries", "chips_fries"),
    # coarse liquids
    ("espresso-with-caffeine", "coffee"),
    ("wine-red", "wine"),
    ("champagne", "wine"),
    ("soup-pumpkin", "soup"),
    ("juice-orange", "fruit_juice"),
])
def test_curated_routings(palette, source, target):
    index, name, rule = b22.route_2022(source, palette)
    assert name == target
    assert rule == "curated_food"
    assert index == palette.index(target)


def test_unhomed_drink_stays_unsupported(palette):
    index, name, rule = b22.route_2022("coca-cola", palette)
    assert index == b22.UNSUPPORTED_LIQUID
    assert name == "unsupported_liquid"
    assert rule == "curated_liquid"


def test_plant_milk_is_not_dairy_milk(palette):
    # oat/soy milk carbs differ from the dairy milk row; they must never
    # inherit the milk channel's composition.
    for source in ("oat-milk", "soya-drink-soy-milk"):
        index, _, _ = b22.route_2022(source, palette)
        assert index == b22.UNSUPPORTED_LIQUID


def test_sauce_family_drops(palette):
    for source in ("bolognaise-sauce", "mayonnaise", "salad-dressing"):
        index, name, rule = b22.route_2022(source, palette)
        assert index is None
        assert rule == "curated_drop"


def test_unlisted_food_defaults_to_unknown_food(palette):
    index, name, rule = b22.route_2022("tiramisu", palette)
    assert index == b22.UNKNOWN_FOOD
    assert rule == "default_unknown_food"


def test_stale_curated_rule_fails_the_build(palette):
    categories = {1: "rice", 2: "water"}
    with pytest.raises(SystemExit, match="stale"):
        b22.build_mapping(palette, categories)


# ── committed artefact ──────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def committed():
    return json.loads(COMMITTED_MAPPING.read_text())


def test_committed_mapping_shape(committed):
    assert committed["schema"] == "foodrec2022_to_palette"
    assert committed["palette_version"] == "v0"
    assert committed["channel_count"] == CHANNEL_COUNT
    assert committed["special_channels"] == {
        "background": TOTAL_CLASSES,
        "unknown_food": TOTAL_CLASSES + 1,
        "unsupported_liquid": TOTAL_CLASSES + 2,
    }
    assert len(committed["mappings"]) == 498


def test_committed_mapping_matches_the_rules(palette, committed):
    # The committed artefact must be a pure function of the current rules —
    # a stale regeneration fails here (Decision 23 invariant).
    for m in committed["mappings"]:
        index, name, rule = b22.route_2022(m["source_name"], palette)
        assert (m["target_index"], m["target_name"], m["rule"]) == \
            (index, name, rule), m["source_name"]


def test_committed_mapping_covers_target_classes(committed):
    by_target = {}
    for m in committed["mappings"]:
        if m["rule"] == "curated_food":
            by_target.setdefault(m["target_name"], []).append(m["source_name"])
    for target in ("cereal", "brown_rice", "bread_wholemeal", "potato_mashed"):
        assert by_target.get(target), f"no source categories route to {target}"
    # beans_baked has no menuCH home — documented in the coverage audit.
    assert "beans_baked" not in by_target

#!/usr/bin/env python3
"""Build the FoodSeg103 -> 27-channel palette class mapping (ml-training §3b).

FoodSeg103 ships 103 food classes (+ a background class 0); the medata segmenter
emits **27 channels** (Req 8.4):

    channels 0-23 : the 24 food classes, in the EXACT order of
                    ``tools/food_db/generate.py`` FOOD_DATA (== ClassPalette.v1Standard)
    channel  24   : background
    channel  25   : unknown_food        (looks like food, no known class)
    channel  26   : unsupported_liquid   (standalone liquid, excluded from volume)

This script is the load-bearing first step of dataset preparation: every
downstream artefact (remapped masks, training, mIoU bench) indexes by these
integer channel offsets, and the Swift runtime indexes the ProbabilityTensor by
the same offsets. Reorder the food classes and the on-device pipeline breaks
silently (design §3.5). So the channel order is read straight from
``generate.py`` rather than hand-typed here.

Each FoodSeg103 class is routed to exactly one of:
    * one of the 24 food channels (direct synonym match),
    * a composite food channel (e.g. assorted veg -> ``mixed_vegetables``),
    * ``unknown_food`` (25) when it is food but has no sensible palette home,
    * ``unsupported_liquid`` (26) for standalone drinks,
    * dropped (``target_index: null``) when it cannot be remapped sensibly.

Output is a deterministic JSON file consumed by ``prepare_dataset.py``.

Usage::

    python tools/segmenter/build_class_mapping.py \\
        --foodseg-labels data/foodseg103/category_id.txt \\
        --palette tools/food_db/generate.py \\
        --out tools/segmenter/class_mapping_foodseg103_v1.json

``--foodseg-labels`` is optional: omit it and the script falls back to the
canonical FoodSeg103 category list embedded below, which makes the script
runnable (and smoke-testable) before the dataset is downloaded.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

PALETTE_VERSION = "v1"

# Special (non-food) channels, fixed by Req 8.4 / ClassPalette.v1Standard.
BACKGROUND = 24
UNKNOWN_FOOD = 25
UNSUPPORTED_LIQUID = 26

# Canonical FoodSeg103 category list (id -> name), used when --foodseg-labels is
# not supplied. id 0 is background; 1..103 are food classes. Names follow the
# dataset's category_id.txt; matching is done on a normalised form so minor
# spelling/spacing differences in a real file still resolve.
CANONICAL_FOODSEG103: Dict[int, str] = {
    0: "background",
    1: "candy", 2: "egg tart", 3: "french fries", 4: "chocolate", 5: "biscuit",
    6: "popcorn", 7: "pudding", 8: "ice cream", 9: "cheese butter", 10: "cake",
    11: "wine", 12: "milkshake", 13: "coffee", 14: "juice", 15: "milk",
    16: "tea", 17: "almond", 18: "red beans", 19: "cashew",
    20: "dried cranberries", 21: "soy", 22: "walnut", 23: "peanut", 24: "egg",
    25: "apple", 26: "date", 27: "apricot", 28: "avocado", 29: "banana",
    30: "strawberry", 31: "cherry", 32: "blueberry", 33: "raspberry",
    34: "mango", 35: "olives", 36: "peach", 37: "lemon", 38: "pear", 39: "fig",
    40: "pineapple", 41: "grape", 42: "kiwi", 43: "melon", 44: "orange",
    45: "watermelon", 46: "steak", 47: "pork", 48: "chicken duck",
    49: "sausage", 50: "fried meat", 51: "lamb", 52: "sauce", 53: "crab",
    54: "fish", 55: "shellfish", 56: "shrimp", 57: "soup", 58: "bread",
    59: "corn", 60: "hamburg", 61: "pizza", 62: "hanamaki baozi",
    63: "wonton dumplings", 64: "pasta", 65: "noodles", 66: "rice", 67: "pie",
    68: "tofu", 69: "eggplant", 70: "potato", 71: "garlic", 72: "cauliflower",
    73: "tomato", 74: "kelp", 75: "seaweed", 76: "spring onion", 77: "rape",
    78: "ginger", 79: "okra", 80: "lettuce", 81: "pumpkin", 82: "cucumber",
    83: "white radish", 84: "carrot", 85: "asparagus", 86: "bamboo shoots",
    87: "broccoli", 88: "celery stick", 89: "cilantro mint", 90: "snow peas",
    91: "cabbage", 92: "bean sprouts", 93: "onion", 94: "pepper",
    95: "green beans", 96: "french beans", 97: "king oyster mushroom",
    98: "shiitake", 99: "enoki mushroom", 100: "oyster mushroom",
    101: "white button mushroom", 102: "salad", 103: "other ingredients",
}

# Curated FoodSeg103 -> palette routing, keyed by normalised FoodSeg103 name.
# Values are a palette food-class id (string, must exist in generate.py),
# the literal "unknown_food"/"unsupported_liquid"/"background", or "drop".
# Anything not listed here defaults to unknown_food (food but unmapped).
CURATED_RULES: Dict[str, str] = {
    # direct / near-direct to a palette food class
    "rice": "white_rice",
    "pasta": "pasta",
    "noodles": "pasta",
    "bread": "bread_white",
    "french fries": "chips_fries",
    "potato": "potato_boiled",
    "chicken duck": "chicken",
    "steak": "beef",
    "fried meat": "beef",
    "lamb": "beef",
    "pork": "pork",
    "sausage": "pork",
    "fish": "fish_white",
    "egg": "egg",
    "egg tart": "egg",
    "cheese butter": "cheese",
    "lettuce": "salad_leaves",
    "salad": "salad_leaves",
    "broccoli": "broccoli",
    "carrot": "carrot",
    "snow peas": "peas",
    "green beans": "peas",
    "french beans": "peas",
    "red beans": "lentils",
    "apple": "apple",
    "banana": "banana",
    "tomato": "tomato",
    # composites -> mixed_vegetables (single-region annotation, Decision 8)
    "cauliflower": "mixed_vegetables",
    "eggplant": "mixed_vegetables",
    "pumpkin": "mixed_vegetables",
    "cucumber": "mixed_vegetables",
    "cabbage": "mixed_vegetables",
    "onion": "mixed_vegetables",
    "pepper": "mixed_vegetables",
    "asparagus": "mixed_vegetables",
    "bamboo shoots": "mixed_vegetables",
    "bean sprouts": "mixed_vegetables",
    "spring onion": "mixed_vegetables",
    "okra": "mixed_vegetables",
    "white radish": "mixed_vegetables",
    "celery stick": "mixed_vegetables",
    "king oyster mushroom": "mixed_vegetables",
    "shiitake": "mixed_vegetables",
    "enoki mushroom": "mixed_vegetables",
    "oyster mushroom": "mixed_vegetables",
    "white button mushroom": "mixed_vegetables",
    "corn": "mixed_vegetables",
    # standalone liquids -> unsupported_liquid (26)
    "wine": "unsupported_liquid",
    "milkshake": "unsupported_liquid",
    "coffee": "unsupported_liquid",
    "juice": "unsupported_liquid",
    "milk": "unsupported_liquid",
    "tea": "unsupported_liquid",
    "soup": "unsupported_liquid",
    # explicit background
    "background": "background",
    # non-food garnish / catch-all that should not pollute a food class
    "sauce": "drop",
    "other ingredients": "drop",
}


def normalise(name: str) -> str:
    """Lowercase, collapse separators/whitespace so file names match the rules."""
    n = name.strip().lower().replace("_", " ").replace("-", " ")
    return re.sub(r"\s+", " ", n).strip()


def parse_palette(generate_py: Path) -> List[str]:
    """Extract the 24 food class ids, in order, from generate.py FOOD_DATA.

    Reads the first string of each FOOD_DATA tuple. The order is load-bearing
    (== channel index), so the list is returned exactly as it appears.
    """
    text = generate_py.read_text(encoding="utf-8")
    m = re.search(r"FOOD_DATA\s*=\s*\[(.*?)\]", text, re.DOTALL)
    if not m:
        raise SystemExit(f"could not find FOOD_DATA list in {generate_py}")
    body = m.group(1)
    # First quoted string on each tuple line is the class_id.
    ids: List[str] = []
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("("):
            continue
        sm = re.search(r'"([^"]+)"', line)
        if sm:
            ids.append(sm.group(1))
    if len(ids) != 24:
        raise SystemExit(
            f"expected 24 food classes in FOOD_DATA, found {len(ids)}: {ids}"
        )
    return ids


def parse_foodseg_labels(path: Path) -> Dict[int, str]:
    """Parse a FoodSeg103 category_id.txt (``<id>\\t<name>`` per line).

    Tolerates a header line and either tab or whitespace separation.
    """
    labels: Dict[int, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        parts = line.split("\t") if "\t" in line else line.split(None, 1)
        if len(parts) < 2:
            continue
        idx_str, name = parts[0].strip(), parts[1].strip()
        if not idx_str.isdigit():  # skip header rows like "id\tname"
            continue
        labels[int(idx_str)] = name
    if not labels:
        raise SystemExit(f"no '<id>\\t<name>' rows parsed from {path}")
    return labels


def route(
    foodseg_name: str, palette: List[str]
) -> Tuple[Optional[int], str, str]:
    """Map one FoodSeg103 name -> (target_index, target_name, rule)."""
    key = normalise(foodseg_name)
    food_index = {name: i for i, name in enumerate(palette)}

    rule = CURATED_RULES.get(key)
    if rule is None:
        # Food, but no curated home -> unknown_food bucket.
        return UNKNOWN_FOOD, "unknown_food", "default_unknown_food"
    if rule == "drop":
        return None, "dropped", "curated_drop"
    if rule == "background":
        return BACKGROUND, "background", "curated_background"
    if rule == "unsupported_liquid":
        return UNSUPPORTED_LIQUID, "unsupported_liquid", "curated_liquid"
    if rule == "unknown_food":
        return UNKNOWN_FOOD, "unknown_food", "curated_unknown_food"
    # Otherwise rule is a palette food-class id.
    if rule not in food_index:
        raise SystemExit(
            f"curated rule maps '{foodseg_name}' -> '{rule}', "
            f"which is not a palette class. Fix CURATED_RULES or the palette."
        )
    return food_index[rule], rule, "curated_food"


def build_mapping(
    palette: List[str], foodseg_labels: Dict[int, str]
) -> dict:
    target_channels = [{"index": i, "name": n} for i, n in enumerate(palette)]
    target_channels += [
        {"index": BACKGROUND, "name": "background"},
        {"index": UNKNOWN_FOOD, "name": "unknown_food"},
        {"index": UNSUPPORTED_LIQUID, "name": "unsupported_liquid"},
    ]

    mappings = []
    for src_id in sorted(foodseg_labels):
        name = foodseg_labels[src_id]
        target_index, target_name, rule = route(name, palette)
        mappings.append(
            {
                "source_id": src_id,
                "source_name": name,
                "target_index": target_index,
                "target_name": target_name,
                "rule": rule,
            }
        )

    return {
        "schema": "foodseg103_to_palette_v1",
        "palette_version": PALETTE_VERSION,
        "source_dataset": "FoodSeg103",
        "channel_count": len(palette) + 3,
        "special_channels": {
            "background": BACKGROUND,
            "unknown_food": UNKNOWN_FOOD,
            "unsupported_liquid": UNSUPPORTED_LIQUID,
        },
        "target_channels": target_channels,
        "mappings": mappings,
    }


def summarise(mapping: dict) -> str:
    counts: Dict[str, int] = {}
    for m in mapping["mappings"]:
        counts[m["rule"]] = counts.get(m["rule"], 0) + 1
    dropped = [m["source_name"] for m in mapping["mappings"]
               if m["target_index"] is None]
    lines = [f"  {rule}: {n}" for rule, n in sorted(counts.items())]
    out = "[build_class_mapping] routing summary:\n" + "\n".join(lines)
    if dropped:
        out += f"\n  dropped classes: {', '.join(dropped)}"
    return out


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--foodseg-labels", default=None,
                        help="FoodSeg103 category_id.txt; omit to use the "
                             "embedded canonical list.")
    parser.add_argument("--palette", default="tools/food_db/generate.py",
                        help="Path to generate.py (source of the 24-class order).")
    parser.add_argument("--out",
                        default="tools/segmenter/class_mapping_foodseg103_v1.json")
    args = parser.parse_args(argv)

    palette = parse_palette(Path(args.palette))

    if args.foodseg_labels:
        labels = parse_foodseg_labels(Path(args.foodseg_labels))
    else:
        print("[build_class_mapping] no --foodseg-labels; using embedded "
              "canonical FoodSeg103 list", file=sys.stderr)
        labels = dict(CANONICAL_FOODSEG103)

    mapping = build_mapping(palette, labels)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(mapping, indent=2) + "\n", encoding="utf-8")

    print(f"[build_class_mapping] wrote {out} "
          f"({len(mapping['mappings'])} source classes -> "
          f"{mapping['channel_count']} channels)")
    print(summarise(mapping))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Build the Food Recognition 2022 -> 36-channel palette class mapping (MD-30).

The myfoodrepo-bridge PRD (dataset-bridge task 3, amended by MD-30) bridges the
AIcrowd Food Recognition Benchmark 2022 release — 498 fine-grained menuCH-style
categories — into the medata v2 palette (25 solid + 8 coarse liquid channels +
background/unknown_food/unsupported_liquid sentinels). Channel order is read
from ``tools/food_db/generate.py`` exactly as ``build_class_mapping.py`` does;
the routing tiers are also identical:

    * curated_food        -> one of the 33 real channels
    * curated_liquid      -> unsupported_liquid (standalone drink, no home)
    * curated_drop        -> dropped (sauces/dressings/condiments/garnish that
                             would pollute a food class; FoodSeg103 "sauce"
                             precedent)
    * default_unknown_food-> everything else: real food with no palette home.
                             With 498 fine categories this bucket is large BY
                             DESIGN — desserts, pastries, nuts, unhomed fruit
                             and composite dishes give the unknown_food
                             sentinel rich, honest supervision.

Source categories come from the dataset's own ``annotations.json`` (ids are
authoritative), so the mapping can never disagree with the annotations it will
be applied to.

Usage::

    python tools/segmenter/build_class_mapping_foodrec2022.py \\
        --annotations data/foodrec2022/raw_data/public_training_set_release_2.0/annotations.json \\
        --palette tools/food_db/generate.py \\
        --out tools/segmenter/class_mapping_foodrec2022_v1.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from build_class_mapping import (
    BACKGROUND,
    PALETTE_VERSION,
    UNKNOWN_FOOD,
    UNSUPPORTED_LIQUID,
    normalise,
    parse_palette,
)

# Curated Food-Recognition-2022 -> palette routing, keyed by normalised
# category name (hyphens collapse to spaces). Values are a palette food-class
# id, "unsupported_liquid", or "drop". Anything not listed defaults to
# unknown_food.
CURATED_RULES_2022: Dict[str, str] = {
    # ── staple carbs ────────────────────────────────────────────────────────
    "rice": "white_rice",
    "rice basmati": "white_rice",
    "rice jasmin": "white_rice",
    "rice whole grain": "brown_rice",
    "rice wild": "brown_rice",
    "pasta": "pasta",
    "pasta hornli": "pasta",
    "pasta in butterfly form farfalle": "pasta",
    "pasta in conch form": "pasta",
    "pasta linguini parpadelle tagliatelle": "pasta",
    "pasta noodles": "pasta",
    "pasta penne": "pasta",
    "pasta ravioli stuffing": "pasta",
    "pasta spaghetti": "pasta",
    "pasta tortelloni stuffing": "pasta",
    "pasta twist": "pasta",
    "pasta wholemeal": "pasta",
    "rice noodles vermicelli": "pasta",   # noodles -> pasta (FoodSeg precedent)
    "spaetzle": "pasta",
    "bread": "bread_white",
    "bread white": "bread_white",
    "bread french white flour": "bread_white",
    "bread half white": "bread_white",
    "bread toast": "bread_white",
    "bread sourdough": "bread_white",
    "bread ticino": "bread_white",
    "braided white loaf": "bread_white",
    "roll of half white or white flour with large void": "bread_white",
    "white bread with butter eggs and milk": "bread_white",
    "bread wholemeal": "bread_wholemeal",
    "bread whole wheat": "bread_wholemeal",
    "bread wholemeal toast": "bread_wholemeal",
    "bread grain": "bread_wholemeal",
    "bread 5 grain": "bread_wholemeal",
    "bread rye": "bread_wholemeal",
    "bread black": "bread_wholemeal",
    "bread spelt": "bread_wholemeal",
    "rusk wholemeal": "bread_wholemeal",
    "potatoes steamed": "potato_boiled",
    "baked potato": "potato_boiled",
    "mashed potatoes prepared with full fat milk with butter": "potato_mashed",
    "chips french fries": "chips_fries",
    "country fries": "chips_fries",
    "rosti": "chips_fries",
    # ── cereal (the class this bridge exists for, MD-29) ────────────────────
    "birchermuesli prepared no sugar added": "cereal",
    "muesli": "cereal",
    "crunch muesli": "cereal",
    "flakes oat": "cereal",
    "corn flakes": "cereal",
    "porridge prepared with partially skimmed milk": "cereal",
    # ── proteins ────────────────────────────────────────────────────────────
    "chicken": "chicken",
    "chicken breast": "chicken",
    "chicken cut into stripes only meat": "chicken",
    "chicken leg": "chicken",
    "chicken wing": "chicken",
    "chicken nuggets": "chicken",
    "beef": "beef",
    "beef cut into stripes only meat": "beef",
    "beef filet": "beef",
    "beef minced only meat": "beef",
    "beef roast": "beef",
    "beef sirloin steak": "beef",
    "meat": "beef",              # generic meat -> beef (FoodSeg steak precedent)
    "meat balls": "beef",
    "meatloaf": "beef",
    "minced meat": "beef",
    "tartar meat": "beef",
    "lamb": "beef",              # lamb -> beef (FoodSeg precedent)
    "lamb chop": "beef",
    "pork": "pork",
    "pork chop": "pork",
    "pork escalope": "pork",
    "pork roast": "pork",
    "cordon bleu from pork schnitzel fried": "pork",
    "bacon": "pork",
    "bacon cooking": "pork",
    "bacon frying": "pork",
    "bacon raw": "pork",
    "ham": "pork",
    "ham cooked": "pork",
    "ham raw": "pork",
    "sausage": "pork",           # sausage -> pork (FoodSeg precedent)
    "cooked sausage": "pork",
    "frying sausage": "pork",
    "veal sausage": "pork",
    "cervelat": "pork",
    "chorizo": "pork",
    "salami": "pork",
    "wienerli swiss sausage": "pork",
    "smoked cooked sausage of pork and beef meat sausag": "pork",
    "dried meat": "pork",
    "processed meat charcuterie": "pork",
    "fish": "fish_white",
    "cod": "fish_white",
    "perch fillets lake": "fish_white",
    "fish fingers breaded": "fish_white",
    "fish crunchies battered": "fish_white",
    "tuna": "fish_white",
    "tuna in oil drained": "fish_white",
    "salmon": "fish_white",      # only fish channel; coarse by design
    "salmon smoked": "fish_white",
    "anchovies": "fish_white",
    "egg": "egg",
    "egg scrambled prepared": "egg",
    "omelette plain": "egg",
    "cheese": "cheese",
    "brie": "cheese",
    "cheddar": "cheese",
    "emmental cheese": "cheese",
    "gruyere": "cheese",
    "parmesan": "cheese",
    "mozzarella": "cheese",
    "feta": "cheese",
    "halloumi": "cheese",
    "tomme": "cheese",
    "tete de moine": "cheese",
    "hard cheese": "cheese",
    "semi hard cheese": "cheese",
    "soft cheese": "cheese",
    "blue mould cheese": "cheese",
    "goat cheese soft": "cheese",
    "cheese for raclette": "cheese",
    "processed cheese": "cheese",
    "fresh cheese": "cheese",
    "cream cheese": "cheese",
    "cottage cheese": "cheese",
    "philadelphia": "cheese",
    "curd": "cheese",
    "curds natural with at most 10 fidm": "cheese",
    "fondue": "cheese",
    # ── vegetables and fruit with palette homes ─────────────────────────────
    "salad leaf salad green": "salad_leaves",
    "salad lambs ear": "salad_leaves",
    "salad rocket": "salad_leaves",
    "leaf spinach": "salad_leaves",
    "spinach raw": "salad_leaves",
    "mixed salad chopped without sauce": "salad_leaves",
    "witloof chicory": "salad_leaves",
    "broccoli": "broccoli",
    "carrot raw": "carrot",
    "carrot steamed without addition of salt": "carrot",
    "peas": "peas",
    "french beans": "peas",
    "green bean steamed without addition of salt": "peas",
    "lentils": "lentils",
    "lentils green du puy du berry": "lentils",
    "beans kidney": "lentils",   # pulses -> lentils (FoodSeg red-beans precedent)
    "beans white": "lentils",
    "chickpeas": "lentils",
    "apple": "apple",
    "banana": "banana",
    "tomato raw": "tomato",
    "tomato stewed without addition of fat without addition of salt": "tomato",
    "sun dried tomatoe": "tomato",
    # composites -> mixed_vegetables (single-region annotation, Decision 8)
    "vegetables": "mixed_vegetables",
    "mixed vegetables": "mixed_vegetables",
    "vegetable mix peas and carrots": "mixed_vegetables",
    "ratatouille": "mixed_vegetables",
    "vegetable au gratin baked": "mixed_vegetables",
    "eggplant": "mixed_vegetables",
    "zucchini": "mixed_vegetables",
    "zucchini stewed without addition of fat without addition of salt": "mixed_vegetables",
    "cauliflower": "mixed_vegetables",
    "romanesco": "mixed_vegetables",
    "brussel sprouts": "mixed_vegetables",
    "white cabbage": "mixed_vegetables",
    "red cabbage": "mixed_vegetables",
    "savoy cabbage steamed without addition of salt": "mixed_vegetables",
    "chinese cabbage": "mixed_vegetables",
    "sauerkraut": "mixed_vegetables",
    "coleslaw chopped without sauce": "mixed_vegetables",
    "pumpkin": "mixed_vegetables",
    "cucumber": "mixed_vegetables",
    "cucumber pickled": "mixed_vegetables",
    "onion": "mixed_vegetables",
    "pearl onions": "mixed_vegetables",
    "spring onion scallion": "mixed_vegetables",
    "leek": "mixed_vegetables",
    "fennel": "mixed_vegetables",
    "celeriac": "mixed_vegetables",
    "celery": "mixed_vegetables",
    "beetroot raw": "mixed_vegetables",
    "beetroot steamed without addition of salt": "mixed_vegetables",
    "bell pepper red raw": "mixed_vegetables",
    "bell pepper red stewed without addition of fat without addition of salt": "mixed_vegetables",
    "green asparagus": "mixed_vegetables",
    "white asparagus": "mixed_vegetables",
    "artichoke": "mixed_vegetables",
    "kolhrabi": "mixed_vegetables",
    "swiss chard": "mixed_vegetables",
    "spinach steamed without addition of salt": "mixed_vegetables",
    "cream spinach": "mixed_vegetables",
    "mushroom": "mixed_vegetables",
    "mushrooms": "mixed_vegetables",
    "mushroom average stewed without addition of fat without addition of salt": "mixed_vegetables",
    "corn": "mixed_vegetables",
    "sweet corn canned": "mixed_vegetables",
    "red radish": "mixed_vegetables",
    "white radish": "mixed_vegetables",
    "garlic": "mixed_vegetables",
    "alfa sprouts": "mixed_vegetables",
    "mungbean sprouts": "mixed_vegetables",
    "shoots": "mixed_vegetables",
    # ── coarse liquids (Req 7.2) ────────────────────────────────────────────
    "water": "water",
    "water mineral": "water",
    "water with lemon juice": "water",
    "ice cubes": "water",
    "coffee with caffeine": "coffee",
    "coffee decaffeinated": "coffee",
    "espresso with caffeine": "coffee",
    "ristretto with caffeine": "coffee",
    "cappuccino": "coffee",
    "white coffee with caffeine": "coffee",
    "latte macchiato with caffeine": "coffee",
    "tea": "tea",
    "tea black": "tea",
    "tea green": "tea",
    "tea fruit": "tea",
    "tea ginger": "tea",
    "tea peppermint": "tea",
    "tea rooibos": "tea",
    "tea spice": "tea",
    "tea verveine": "tea",
    "herbal tea": "tea",
    "milk": "milk",
    "juice apple": "fruit_juice",
    "juice multifruit": "fruit_juice",
    "juice orange": "fruit_juice",
    "smoothie": "fruit_juice",
    "bouillon": "soup",
    "bouillon vegetable": "soup",
    "soup cream of vegetables": "soup",
    "soup miso": "soup",
    "soup of lentils dahl dhal": "soup",
    "soup potato": "soup",
    "soup pumpkin": "soup",
    "soup tomato": "soup",
    "soup vegetable": "soup",
    "beer": "beer",
    "light beer": "beer",
    "wine red": "wine",
    "wine white": "wine",
    "wine rose": "wine",
    "champagne": "wine",
    "prosecco": "wine",
    "sekt": "wine",
    # standalone drinks with no palette home
    "coca cola": "unsupported_liquid",
    "coca cola zero": "unsupported_liquid",
    "ice tea": "unsupported_liquid",          # sweetened, not the tea channel
    "syrup diluted ready to drink": "unsupported_liquid",
    "glucose drink 50g": "unsupported_liquid",
    "cocktail": "unsupported_liquid",
    "aperitif with alcohol aperol spritz": "unsupported_liquid",
    "chocolate milk chocolate drink": "unsupported_liquid",
    "kefir drink": "unsupported_liquid",
    "oat milk": "unsupported_liquid",         # plant milks: not dairy-milk carbs
    "soya drink soy milk": "unsupported_liquid",
    "coconut milk": "unsupported_liquid",
    # ── condiments / dressings / garnish -> drop (FoodSeg "sauce" precedent) ─
    "bolognaise sauce": "drop",
    "tomato sauce": "drop",
    "sauce carbonara": "drop",
    "sauce cocktail": "drop",
    "sauce cream": "drop",
    "sauce curry": "drop",
    "sauce mushroom": "drop",
    "sauce pesto": "drop",
    "sauce roast": "drop",
    "sauce savoury": "drop",
    "sauce soya": "drop",
    "sauce sweet salted asian": "drop",
    "sauce sweet sour": "drop",
    "tartar sauce": "drop",
    "salad dressing": "drop",
    "balsamic salad dressing": "drop",
    "french salad dressing": "drop",
    "italian salad dressing": "drop",
    "oil vinegar salad dressing": "drop",
    "balsamic vinegar": "drop",
    "ketchup": "drop",
    "mayonnaise": "drop",
    "mustard": "drop",
    "mustard dijon": "drop",
    "dips": "drop",
    "oil": "drop",
    "butter": "drop",
    "butter herb": "drop",
    "butter spread puree almond": "drop",
    "margarine": "drop",
    "cream": "drop",
    "sour cream": "drop",
    "thickened cream 35": "drop",
    "honey": "drop",
    "jam": "drop",
    "maple syrup concentrate": "drop",
    "sugar glazing": "drop",
    "cocoa powder": "drop",
    "hazelnut chocolate spread nutella ovomaltine caotina": "drop",
    "peanut butter": "drop",
    "cenovis yeast spread": "drop",
    "breadcrumbs unspiced": "drop",
    "bouquet garni": "drop",
    "basil": "drop",
    "parsley": "drop",
    "chives": "drop",
    "coriander": "drop",
    "capers": "drop",
}


def route_2022(name: str, palette: List[str]) -> Tuple[Optional[int], str, str]:
    """Map one 2022 category name -> (target_index, target_name, rule)."""
    key = normalise(name)
    food_index = {n: i for i, n in enumerate(palette)}

    rule = CURATED_RULES_2022.get(key)
    if rule is None:
        return UNKNOWN_FOOD, "unknown_food", "default_unknown_food"
    if rule == "drop":
        return None, "dropped", "curated_drop"
    if rule == "unsupported_liquid":
        return UNSUPPORTED_LIQUID, "unsupported_liquid", "curated_liquid"
    if rule not in food_index:
        raise SystemExit(
            f"curated rule maps '{name}' -> '{rule}', which is not a palette "
            f"class. Fix CURATED_RULES_2022 or the palette."
        )
    return food_index[rule], rule, "curated_food"


def load_categories(annotations_path: Path) -> Dict[int, str]:
    """id -> name from the dataset's own annotations.json (authoritative)."""
    data = json.loads(annotations_path.read_text(encoding="utf-8"))
    if "categories" not in data:
        raise SystemExit(f"{annotations_path} has no 'categories' key")
    return {int(c["id"]): c["name"] for c in data["categories"]}


def build_mapping(palette: List[str], categories: Dict[int, str]) -> dict:
    # Every curated rule must correspond to a real category — a stale rule
    # (typo, renamed category) must fail the build, not silently no-op.
    known = {normalise(n) for n in categories.values()}
    stale = sorted(k for k in CURATED_RULES_2022 if k not in known)
    if stale:
        raise SystemExit(
            f"curated rules reference {len(stale)} unknown categories "
            f"(stale/typo): {stale[:10]}"
        )

    target_channels = [{"index": i, "name": n} for i, n in enumerate(palette)]
    target_channels += [
        {"index": BACKGROUND, "name": "background"},
        {"index": UNKNOWN_FOOD, "name": "unknown_food"},
        {"index": UNSUPPORTED_LIQUID, "name": "unsupported_liquid"},
    ]

    mappings = []
    for src_id in sorted(categories):
        name = categories[src_id]
        target_index, target_name, rule = route_2022(name, palette)
        mappings.append({
            "source_id": src_id,
            "source_name": name,
            "target_index": target_index,
            "target_name": target_name,
            "rule": rule,
        })

    return {
        "schema": "foodrec2022_to_palette_v1",
        "palette_version": PALETTE_VERSION,
        "source_dataset": "Food Recognition Benchmark 2022 (release 2.0)",
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
    per_target: Dict[str, int] = {}
    for m in mapping["mappings"]:
        counts[m["rule"]] = counts.get(m["rule"], 0) + 1
        if m["rule"] == "curated_food":
            per_target[m["target_name"]] = per_target.get(m["target_name"], 0) + 1
    lines = [f"  {rule}: {n}" for rule, n in sorted(counts.items())]
    lines.append("  curated_food per channel: " + ", ".join(
        f"{k}={v}" for k, v in sorted(per_target.items())))
    return "[build_class_mapping_foodrec2022] routing summary:\n" + "\n".join(lines)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--annotations",
        default="/Users/r/repos/medata/data/foodrec2022/raw_data/"
                "public_training_set_release_2.0/annotations.json",
        help="Dataset annotations.json (source of the authoritative "
             "category ids).")
    parser.add_argument("--palette", default="tools/food_db/generate.py",
                        help="Path to generate.py (source of the channel order).")
    parser.add_argument("--out",
                        default="tools/segmenter/class_mapping_foodrec2022_v1.json")
    args = parser.parse_args(argv)

    palette = parse_palette(Path(args.palette))
    categories = load_categories(Path(args.annotations))
    mapping = build_mapping(palette, categories)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(mapping, indent=2) + "\n", encoding="utf-8")

    print(f"[build_class_mapping_foodrec2022] wrote {out} "
          f"({len(mapping['mappings'])} source classes -> "
          f"{mapping['channel_count']} channels)")
    print(summarise(mapping))
    return 0


if __name__ == "__main__":
    sys.exit(main())

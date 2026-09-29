#!/usr/bin/env python3
"""Build mapping_n5k_to_palette.json from ingredients_metadata.csv (Req 2).

Curation rules live here as reviewable name -> class tables; the committed
artifact is their deterministic output. Re-run when the palette content or
the N5k ingredient metadata changes (the loader fails loudly on either,
Req 2.5)::

    python tools/nutrition5k/build_mapping.py \\
        --metadata-csv data/metadata/ingredients_metadata.csv

Curation policy (design §Mapping artifact):
- Broad coverage: map as many of the 24 solid classes as N5k ingredients
  allow — the 8 carb-priority staples are the floor, not the cap. A plate
  only feeds the mixture path when ALL its significant ingredients map.
- Conservative identity: an ingredient maps only when its preparation and
  composition plausibly match the DB row (e.g. "roasted potatoes" does NOT
  map to potato_boiled; battered/processed/composite dishes stay unmapped).
- Pair-ambiguous ingredients (generic "rice"/"potatoes"/"bread") are
  recorded status=ambiguous and excluded from both sides (Req 2.4).
- Liquid ingredients map to the coarse liquid class ids so routing can
  detect liquid-bearing plates (Req 4.7); they never enter the β fit.
- Everything else is status=unmapped — excluded, never reassigned (Req 2.3).
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))

import mapping  # noqa: E402

_REPO_ROOT = _HERE.parents[1]
DEFAULT_METADATA_CSV = _REPO_ROOT / "data" / "metadata" / "ingredients_metadata.csv"

# N5k ingredient name (as in ingredients_metadata.csv, stripped) -> class id.
MAPPED_RULES: dict[str, str] = {
    # --- carb-priority staples (Req 2.2) ---
    "white rice": "white_rice",
    "brown rice": "brown_rice",
    "pasta": "pasta",
    "spaghetti": "pasta",
    "macaroni": "pasta",
    "noodles": "pasta",          # wheat noodles; rice noodles stay unmapped
    "orzo": "pasta",
    "white bread": "bread_white",
    "sourdough bread": "bread_white",
    "whole wheat bread": "bread_wholemeal",
    "wheat bread": "bread_wholemeal",
    "mashed potatoes": "potato_mashed",
    "french fries": "chips_fries",
    # potato_boiled: no N5k ingredient states the boiled preparation —
    # "potatoes"/"red potatoes" are pair-ambiguous below; "baked"/"roasted
    # potatoes" are a different preparation. Documented staple gap.

    # --- proteins ---
    "chicken": "chicken",
    "chicken breast": "chicken",
    "grilled chicken": "chicken",
    "roast chicken": "chicken",
    "beef": "beef",
    "steak": "beef",
    "roast beef": "beef",
    "pork": "pork",
    "pork chops": "pork",
    "roast pork": "pork",
    # fish_white = "Fish (white, baked)"; oily fish (salmon, tuna, mackerel,
    # sardines, trout, swordfish) and generic "fish" stay unmapped.
    "cod": "fish_white",
    "haddock": "fish_white",
    "tilapia": "fish_white",
    "halibut": "fish_white",
    "flounder": "fish_white",
    "snapper": "fish_white",
    "mahi mahi": "fish_white",
    "catfish": "fish_white",
    "eggs": "egg",
    "hard boiled eggs": "egg",
    "poached eggs": "egg",       # no added fat; fried/scrambled stay unmapped
    # cheese = "Cheddar cheese" (hard/semi-hard); soft high-moisture cheeses
    # (cottage, cream, feta, brie, mozzarella...) stay unmapped.
    "cheese": "cheese",
    "cheddar cheese": "cheese",
    "colby cheese": "cheese",
    "swiss cheese": "cheese",
    "provolone cheese": "cheese",
    "muenster cheese": "cheese",
    "havarti cheese": "cheese",
    "gouda cheese": "cheese",
    "american cheese": "cheese",

    # --- vegetables and fruit ---
    "lettuce": "salad_leaves",
    "mixed greens": "salad_leaves",
    "arugula": "salad_leaves",
    "spinach (raw)": "salad_leaves",
    "broccoli": "broccoli",
    "carrot": "carrot",
    "baby carrots": "carrot",
    "peas": "peas",
    "green peas": "peas",
    "baked beans": "beans_baked",
    "lentils": "lentils",
    "apple": "apple",
    "banana": "banana",
    "tomatoes": "tomato",
    "cherry tomatoes": "tomato",
    "mixed vegetables": "mixed_vegetables",

    # --- coarse liquid classes (routing detection only, Req 4.7) ---
    "water": "water",
    "coffee": "coffee",
    "latte": "coffee",
    "cappuccino": "coffee",
    "tea": "tea",
    "iced tea": "tea",
    "milk": "milk",              # dairy only; plant milks stay unmapped
    "skim milk": "milk",
    "buttermilk": "milk",
    "chocolate milk": "milk",
    "orange juice": "fruit_juice",
    "apple juice": "fruit_juice",
    "grape juice": "fruit_juice",
    "cranberry juice": "fruit_juice",
    "grapefruit juice": "fruit_juice",
    "apple cider": "fruit_juice",
    "lemon juice": "fruit_juice",
    "chicken soup": "soup",
    "tomato soup": "soup",
    "miso soup": "soup",
    "broth": "soup",
    "chowders": "soup",
    "beer": "beer",
    "light beer": "beer",
    "lager": "beer",
    "stout beer": "beer",
    "india pale ale beer": "beer",
    "wheat beer": "beer",
    "wine": "wine",
    "white wine": "wine",
    "champagne": "wine",
}

# Ingredient name -> the MeData class pair N5k's taxonomy cannot distinguish
# (Req 2.4). Recorded ambiguous, excluded from BOTH sides.
AMBIGUOUS_RULES: dict[str, tuple[str, str]] = {
    "rice": ("white_rice", "brown_rice"),
    "potatoes": ("potato_boiled", "potato_mashed"),
    "red potatoes": ("potato_boiled", "potato_mashed"),
    "bread": ("bread_white", "bread_wholemeal"),
}


def build(metadata_csv: Path, class_palette_swift: Path, out_path: Path) -> dict:
    palette = mapping.parse_palette(class_palette_swift)
    palette_set = set(palette.class_list)

    unknown_targets = sorted(
        {c for c in MAPPED_RULES.values() if c not in palette_set}
    )
    if unknown_targets:
        raise SystemExit(f"MAPPED_RULES target non-palette classes: {unknown_targets}")

    entries = []
    seen_rule_names = set()
    with open(metadata_csv, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            name = row["ingr"].strip()
            numeric_id = int(row["id"])
            ingredient_id = mapping.canonical_ingredient_id(numeric_id)
            entry: dict = {
                "n5k_ingredient_id": ingredient_id,
                "n5k_ingredient_name": name,
            }
            if name in MAPPED_RULES:
                entry["class_id"] = MAPPED_RULES[name]
                entry["status"] = mapping.STATUS_MAPPED
                seen_rule_names.add(name)
            elif name in AMBIGUOUS_RULES:
                entry["class_id"] = None
                entry["status"] = mapping.STATUS_AMBIGUOUS
                entry["ambiguous_between"] = list(AMBIGUOUS_RULES[name])
                seen_rule_names.add(name)
            else:
                entry["class_id"] = None
                entry["status"] = mapping.STATUS_UNMAPPED
            entries.append(entry)

    # A rule naming an ingredient the CSV does not contain is a curation typo.
    stale = sorted((set(MAPPED_RULES) | set(AMBIGUOUS_RULES)) - seen_rule_names)
    if stale:
        raise SystemExit(f"rules reference ingredients not in {metadata_csv}: {stale}")

    entries.sort(key=lambda e: e["n5k_ingredient_id"])
    artifact = {
        "palette_class_list": palette.class_list,
        "n5k_metadata_version": mapping.metadata_version(metadata_csv),
        "mappings": entries,
    }
    out_path.write_text(json.dumps(artifact, indent=2) + "\n")

    by_status: dict[str, int] = {}
    for e in entries:
        by_status[e["status"]] = by_status.get(e["status"], 0) + 1
    mapped_classes = sorted({e["class_id"] for e in entries if e["class_id"]})
    print(f"[build-mapping] wrote {out_path}")
    print(f"[build-mapping] {len(entries)} ingredients: {by_status}")
    print(f"[build-mapping] {len(mapped_classes)} classes covered: {mapped_classes}")
    return artifact


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata-csv", default=str(DEFAULT_METADATA_CSV))
    parser.add_argument("--class-palette",
                        default=str(mapping.DEFAULT_CLASS_PALETTE_SWIFT))
    parser.add_argument("--out", default=str(mapping.DEFAULT_ARTIFACT))
    args = parser.parse_args(argv)

    metadata_csv = Path(args.metadata_csv)
    if not metadata_csv.is_file():
        raise SystemExit(
            f"--metadata-csv not found: {metadata_csv} (expected the N5k "
            f"ingredient metadata per specs/estimation/nutrition5k-calibration/"
            f"prerequisites.md)"
        )
    build(metadata_csv, Path(args.class_palette), Path(args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())

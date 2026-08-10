#!/usr/bin/env python3
"""Build mapping_metafood3d_to_palette.json (Req 1.3/1.4, Decision 15).

Curation rules live here as reviewable category -> class tables; the
committed artifact is their deterministic output. Targets the palette v2
content list (``ClassPalette.v2Standard``, Decision 15).

Two build modes:

- **Curated-only** (no ``--categories-file``): the artifact's category
  universe is the rules themselves; ``categories_source`` records the
  ``curated_rules_only`` sentinel. This was the committed mode while the
  dataset was inaccessible; it remains for tests.
- **Enumerated** (``--categories-file``, one category per line): all
  snapshot categories are recorded (unmapped ones included), a stale rule
  aborts the build (curation typo, n5k semantics), and
  ``categories_source`` records the enumeration's SHA-256. The COMMITTED
  artifact is built this way since Decision 20, against
  ``data/metafood3d/categories.txt`` as written by ``derive_metadata.py``
  from the real nutrition workbook (637 objects / 108 categories).

Curation policy (mirrors tools/nutrition5k/build_mapping.py):
- Conservative identity: a category maps only when its preparation and
  composition plausibly match the DB row (battered/processed/composite
  dishes stay unmapped).
- Categories that do not state the cooking method a split class needs
  (generic rice / potato / bread) are recorded status=ambiguous and
  excluded from BOTH sides (Req 1.3) — never guessed.
- Category keys are normalised snake_case (mapping.normalise_category);
  the exact MetaFood3D folder spellings are reconciled via the stale-rule
  check when the gated dataset first lands.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent


def _import_sibling(name: str):
    """Import a sibling tool module under a unique ``metafood3d_<name>``
    sys.modules key. The file names here deliberately mirror
    tools/nutrition5k/ (design parity table), so a plain ``import mapping``
    would collide with the nutrition5k module of the same name when both
    tool test dirs run in one pytest invocation."""
    key = f"metafood3d_{name}"
    if key in sys.modules:
        return sys.modules[key]
    spec = importlib.util.spec_from_file_location(key, _HERE / f"{name}.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[key] = module
    spec.loader.exec_module(module)
    return module


mapping = _import_sibling("mapping")

# MetaFood3D category (normalised) -> palette class name (v2 content).
#
# Rewritten against the REAL 108-category enumeration from the v2
# nutrition workbook (Decision 20) — the earlier blind-written rules
# named categories that do not exist in the dataset. Everything not
# listed here or in AMBIGUOUS_RULES is unmapped: overwhelmingly
# composite dishes (burger, lasagna, sushi), battered/fried items
# (breaded_fish, chicken_nugget, falafel), desserts, and single foods
# the palette has no class for. Notable conservative exclusions:
# bacon/sausages (cured/processed, not the plain pork row),
# chicken_wings/whole_chicken (skin/bone-heavy, unlike the meat row),
# fried_egg/omelet (added fat vs the plain egg row), baked_potato
# (a stated method neither potato class covers), sweet_potato
# (different species), cottage_cheese (unlike the hard-cheese row),
# fried_rice/pasta_mixed_dishes/mac (composites, not plain staples).
MAPPED_RULES: dict[str, str] = {
    # --- carb-priority staples ---
    "french_fry": "chips_fries",
    "mashed_potato": "potato_mashed",

    # --- proteins ---
    "chicken_breast": "chicken",
    "chicken_thighs": "chicken",   # plain cooked chicken meat; dark vs
                                   # light is within-class variation
    "steak": "beef",
    "pork_chop": "pork",
    "egg": "egg",

    # --- vegetables and fruit ---
    "broccoli": "broccoli",
    "carrot": "carrot",
    "apple": "apple",
    "banana": "banana",
    "tomato": "tomato",
    "tomato_slice": "tomato",      # same food, cut — composition identical
}

# Category -> the MeData class pair the category name cannot distinguish
# (Req 1.3). Recorded ambiguous, excluded from BOTH sides, never guessed.
AMBIGUOUS_RULES: dict[str, tuple[str, str]] = {
    "rice": ("white_rice", "brown_rice"),
    "yeast_bread": ("bread_white", "bread_wholemeal"),
}


def categories_digest(categories: list[str]) -> str:
    """SHA-256 over the sorted normalised enumeration — the operational
    category-snapshot identifier (Req 9.1)."""
    joined = "\n".join(sorted(mapping.normalise_category(c) for c in categories))
    return hashlib.sha256(joined.encode()).hexdigest()


def build(categories: list[str] | None,
          class_palette_swift: str | Path,
          out_path: str | Path) -> dict:
    palette = mapping.parse_palette(class_palette_swift)
    palette_set = set(palette.class_list)
    out_path = Path(out_path)

    unknown_targets = sorted(
        {c for c in MAPPED_RULES.values() if c not in palette_set}
    )
    if unknown_targets:
        raise SystemExit(f"MAPPED_RULES target non-palette classes: {unknown_targets}")
    unknown_pair_targets = sorted(
        {c for pair in AMBIGUOUS_RULES.values() for c in pair
         if c not in palette_set}
    )
    if unknown_pair_targets:
        raise SystemExit(
            f"AMBIGUOUS_RULES reference non-palette classes: {unknown_pair_targets}")

    if categories is None:
        universe = sorted(set(MAPPED_RULES) | set(AMBIGUOUS_RULES))
        source = mapping.CURATED_ONLY_SOURCE
    else:
        universe = sorted({mapping.normalise_category(c) for c in categories})
        # A rule naming a category the enumeration lacks is a curation typo
        # (n5k stale-check semantics).
        stale = sorted((set(MAPPED_RULES) | set(AMBIGUOUS_RULES)) - set(universe))
        if stale:
            raise SystemExit(
                f"rules reference categories not in the enumeration: {stale}")
        source = categories_digest(categories)

    entries = []
    for category in universe:
        entry: dict = {"category": category}
        if category in MAPPED_RULES:
            entry["class_id"] = MAPPED_RULES[category]
            entry["status"] = mapping.STATUS_MAPPED
        elif category in AMBIGUOUS_RULES:
            entry["class_id"] = None
            entry["status"] = mapping.STATUS_AMBIGUOUS
            entry["ambiguous_between"] = list(AMBIGUOUS_RULES[category])
        else:
            entry["class_id"] = None
            entry["status"] = mapping.STATUS_UNMAPPED
        entries.append(entry)

    artifact = {
        "palette_class_list": palette.class_list,
        "categories_source": source,
        "mappings": entries,
    }
    out_path.write_text(json.dumps(artifact, indent=2) + "\n")

    counts: dict[str, int] = {}
    for e in entries:
        counts[e["status"]] = counts.get(e["status"], 0) + 1
    mapped_classes = sorted({e["class_id"] for e in entries if e["class_id"]})
    print(f"[build-mapping] wrote {out_path}")
    print(f"[build-mapping] {len(entries)} categories: {counts}")
    print(f"[build-mapping] {len(mapped_classes)} classes covered: {mapped_classes}")
    return {"artifact": artifact, "counts": counts}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--categories-file", default="",
        help="optional enumeration of the dataset snapshot's categories, "
             "one per line (regenerate the artifact with this once the "
             "gated dataset lands)")
    parser.add_argument("--class-palette",
                        default=str(mapping.DEFAULT_CLASS_PALETTE_SWIFT))
    parser.add_argument("--out", default=str(mapping.DEFAULT_ARTIFACT))
    args = parser.parse_args(argv)

    categories: list[str] | None = None
    if args.categories_file:
        path = Path(args.categories_file)
        if not path.is_file():
            raise SystemExit(f"--categories-file not found: {path}")
        categories = [line for line in path.read_text().splitlines()
                      if line.strip()]
    build(categories, Path(args.class_palette), Path(args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())

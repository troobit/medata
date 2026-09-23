#!/usr/bin/env python3
"""External co-occurrence statistics from a Recipe1M+-style corpus (Req 6.1).

The co-occurrence loss (segmenter-foundation design §4.3) trains against
presence priors that ``prepare_dataset.py`` derives from the FoodSeg103 train
split — ~5.5k images, so thin classes get thin priors. This tool derives the
same statistics from an EXTERNAL ingredient corpus (Recipe1M+ or equivalent):
each recipe's ingredient list is mapped onto the 35-class palette through the
committed, reviewable ``ingredient_mapping_recipe1m.json`` (the
class-mapping precedent), and each recipe contributes one presence set —
exactly the per-image presence convention of ``prepare_dataset.build_co_stats``.

Output is the ``co_stats`` shape amended for corpus provenance (snaq-parity
Decision 13): ``source: "recipe1m"``, ``split_seed: null`` (corpus statistics
are split-independent; ``loss_config.load_co_stats`` accepts the null seed
only for an external source), the ingredient-mapping SHA-256, and the
palette-coverage lists (which classes gained external statistics — Req 6.1).
``class_mapping_sha256`` still stamps PALETTE identity: this tool never reads
FoodSeg103 annotations, but the priors are only valid for the palette whose
committed class mapping hashes to that value. ``pixel_counts`` and
``train_images`` are explicit nulls — a recipe corpus has neither.

Validation failures fail THIS tool, never the training run (design Error
Handling): an unmapped-ingredient rate above ``--max-unmapped-rate`` means the
mapping does not fit the corpus, and a food class with zero corpus presence
would silently give every false presence of it the full pair-gain up-weight
with no evidence — both abort before any file is written. ``train.py``'s
fail-fast launch contract is unchanged; point it at the emitted file with
``--co-stats``.

Usage::

    python tools/segmenter/build_external_co_stats.py \\
        --corpus path/to/recipe1m_layer1.json \\
        --out data/foodseg103_remapped/co_stats_recipe1m.json

Pure stdlib + json — runs and is tested without the training venv; obtaining
the real corpus is human-gated (prerequisites.md).
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

# The corpus source this tool derives from; stamped into the output and
# accepted by loss_config.EXTERNAL_CO_STATS_SOURCES.
SOURCE = "recipe1m"

# Above this unmapped-ingredient rate the mapping evidently does not fit the
# corpus and the derived priors would be built from scraps. Recipe1M+-style
# corpora are dominated by seasonings/oils outside the 32-class food palette,
# so the default bar is deliberately high; tighten per corpus via the flag.
DEFAULT_MAX_UNMAPPED_RATE = 0.95

_MAPPING_PATH = Path(__file__).resolve().with_name("ingredient_mapping_recipe1m.json")
_CLASS_MAPPING_PATH = Path(__file__).resolve().with_name("class_mapping_foodseg103.json")

_NON_WORD = re.compile(r"[^a-z0-9]+")


def _load_lineage_module():
    """Import the sibling lineage.py by path (pure stdlib; no torch needed)."""
    lineage_path = Path(__file__).resolve().with_name("lineage.py")
    spec = importlib.util.spec_from_file_location("segmenter_lineage", lineage_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Could not load sibling lineage module at {lineage_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def normalise_ingredient(text: str) -> str:
    """Lowercase, strip punctuation to spaces, collapse whitespace — the
    canonical form both the mapping terms and the corpus texts match in."""
    return _NON_WORD.sub(" ", text.lower()).strip()


def map_ingredient(text: str, mappings: Mapping[str, str]) -> str | None:
    """Map one ingredient text to a palette class name, or None when unmapped.

    A term matches when it appears as a word-boundary phrase inside the
    normalised text. The LONGEST matching term wins (most words, then most
    characters, then alphabetical for determinism), so ``wholemeal bread``
    beats the generic ``bread`` and ``chicken soup`` resolves to soup.
    """
    padded = f" {normalise_ingredient(text)} "
    best: tuple[int, int, str] | None = None
    best_class: str | None = None
    for term, class_name in mappings.items():
        if f" {term} " not in padded:
            continue
        # Sort key: more words, then longer, then FIRST alphabetically — the
        # comparison inverts the term so min-alphabetical wins under >.
        key = (term.count(" ") + 1, len(term), term)
        if best is None or (key[:2] > best[:2]
                            or (key[:2] == best[:2] and key[2] < best[2])):
            best = key
            best_class = class_name
    return best_class


def load_corpus(path: str | Path) -> list[list[str]]:
    """Load a Recipe1M+-style corpus: a JSON list of recipes whose
    ``ingredients`` entries are ``{"text": ...}`` objects (the layer1 shape)
    or plain strings. Returns one list of ingredient texts per recipe."""
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise SystemExit(f"[co-stats] {path}: expected a JSON list of recipes")
    recipes: list[list[str]] = []
    for recipe in raw:
        ingredients = recipe.get("ingredients", []) if isinstance(recipe, dict) else recipe
        texts = [
            item["text"] if isinstance(item, dict) else str(item)
            for item in ingredients
        ]
        recipes.append(texts)
    return recipes


def count_presence(
    presence_sets: Iterable[set[int]],
    channel_count: int,
    special_channel_indices: Sequence[int],
) -> tuple[list[int], list[list[int]]]:
    """Presence and joint-presence counts over per-recipe class sets — the
    ``prepare_dataset.build_co_stats`` convention: food channels only
    (Decision 20), special rows/columns held at zero so indices remain
    palette indices."""
    specials = {int(c) for c in special_channel_indices}
    presence = [0] * channel_count
    joint = [[0] * channel_count for _ in range(channel_count)]
    for present in presence_sets:
        classes = sorted(c for c in present if c not in specials)
        for c in classes:
            presence[c] += 1
            for k in classes:
                joint[c][k] += 1
    return presence, joint


def build_external_co_stats(
    recipes: Sequence[Sequence[str]],
    ingredient_mapping: Mapping[str, Any],
    class_mapping: Mapping[str, Any],
    *,
    ingredient_mapping_sha256: str,
    max_unmapped_rate: float = DEFAULT_MAX_UNMAPPED_RATE,
) -> dict[str, Any]:
    """Assemble the external ``co_stats`` dict (see module docstring).

    Raises ``SystemExit`` when the unmapped-ingredient rate exceeds
    ``max_unmapped_rate`` or any food class has zero corpus presence — the
    tool fails, the training run never sees a bad file.
    """
    mappings = dict(ingredient_mapping["mappings"])
    channel_count = int(class_mapping["channel_count"])
    specials = sorted(int(c) for c in class_mapping["special_channels"].values())
    name_to_index = {
        c["name"]: int(c["index"]) for c in class_mapping["target_channels"]
    }
    special_names = set(class_mapping["special_channels"])
    bad_targets = sorted(
        {t for t in mappings.values()
         if t not in name_to_index or t in special_names}
    )
    if bad_targets:
        raise SystemExit(
            f"[co-stats] ingredient mapping targets outside the food palette: "
            f"{', '.join(bad_targets)}"
        )

    total = 0
    unmapped = 0
    presence_sets: list[set[int]] = []
    for texts in recipes:
        present: set[int] = set()
        for text in texts:
            total += 1
            class_name = map_ingredient(text, mappings)
            if class_name is None:
                unmapped += 1
            else:
                present.add(name_to_index[class_name])
        presence_sets.append(present)

    rate = (unmapped / total) if total else 1.0
    if rate > max_unmapped_rate:
        raise SystemExit(
            f"[co-stats] unmapped-ingredient rate {rate:.3f} exceeds the "
            f"threshold {max_unmapped_rate} ({unmapped}/{total} ingredient "
            "texts unmapped) — the mapping does not fit this corpus; extend "
            f"{_MAPPING_PATH.name} or pass --max-unmapped-rate deliberately"
        )

    presence, joint = count_presence(presence_sets, channel_count, specials)
    food_names = [
        name for name, idx in sorted(name_to_index.items(), key=lambda kv: kv[1])
        if name not in special_names
    ]
    without = [name for name in food_names if presence[name_to_index[name]] == 0]
    covered = [name for name in food_names if presence[name_to_index[name]] > 0]
    if without:
        raise SystemExit(
            "[co-stats] zero external statistics for palette classes: "
            f"{', '.join(without)} — priors of zero would up-weight every "
            "false presence of these classes with no evidence; extend the "
            "corpus or the ingredient mapping"
        )

    lineage = _load_lineage_module()
    return {
        "schema": "co_stats",
        "source": str(ingredient_mapping.get("source", SOURCE)),
        "split_seed": None,  # corpus statistics are split-independent
        "class_mapping_sha256": lineage.file_sha256(_CLASS_MAPPING_PATH),
        "ingredient_mapping_sha256": ingredient_mapping_sha256,
        "channel_count": channel_count,
        "special_channel_indices": specials,
        "corpus_recipes": len(recipes),
        "unmapped_ingredient_rate": rate,
        "palette_coverage": {
            "with_statistics": covered,
            "without_statistics": without,
        },
        # A recipe corpus has no pixels and no train split — explicit nulls
        # keep the co_stats key set while claiming nothing false.
        "pixel_counts": None,
        "train_images": None,
        "presence_counts": presence,
        "joint_presence_counts": joint,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--corpus", required=True,
                        help="Recipe1M+-style JSON corpus (list of recipes with "
                             "'ingredients' text entries).")
    parser.add_argument("--mapping", default=str(_MAPPING_PATH),
                        help="Committed ingredient→class mapping "
                             "(default: ingredient_mapping_recipe1m.json).")
    parser.add_argument("--out", required=True,
                        help="Where to write the external co_stats.json; point "
                             "train.py at it with --co-stats.")
    parser.add_argument("--max-unmapped-rate", type=float,
                        default=DEFAULT_MAX_UNMAPPED_RATE,
                        help="Fail above this unmapped-ingredient rate "
                             f"(default {DEFAULT_MAX_UNMAPPED_RATE}).")
    args = parser.parse_args(argv)

    lineage = _load_lineage_module()
    mapping_path = Path(args.mapping)
    stats = build_external_co_stats(
        load_corpus(args.corpus),
        json.loads(mapping_path.read_text(encoding="utf-8")),
        json.loads(_CLASS_MAPPING_PATH.read_text(encoding="utf-8")),
        ingredient_mapping_sha256=lineage.file_sha256(mapping_path),
        max_unmapped_rate=args.max_unmapped_rate,
    )
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8")
    coverage = stats["palette_coverage"]
    print(f"[co-stats] {stats['corpus_recipes']} recipes -> {out} "
          f"(source={stats['source']}, unmapped rate "
          f"{stats['unmapped_ingredient_rate']:.3f}, "
          f"{len(coverage['with_statistics'])} classes covered)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

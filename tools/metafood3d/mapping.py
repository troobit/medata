"""MetaFood3D category -> palette class mapping artifact loader (Req 1.3/1.4).

The artifact (``mapping_metafood3d_to_palette.json``, built by
``build_mapping.py``) is versioned against the palette **v2** CONTENT — the
ordered class list parsed from ``ClassPalette.swift`` ``v2Standard`` (25
solid classes with ``cereal`` at index 24, then 8 coarse liquid classes;
sentinels excluded). Decision 15: β is keyed by class NAME end-to-end, so
the content lock (not channel ordering) is what this artifact preserves,
and the loader fails loudly when the artifact was built against different
palette content.

Unlike Nutrition5k's ``ingredients_metadata.csv``, MetaFood3D ships no
public category enumeration (access is request-gated), so the committed
artifact's category universe is the curated rules themselves. At ingest
time, a dataset category absent from the artifact is excluded and counted
(Req 1.4) — never guessed.

Statuses form a closed vocabulary:

- ``mapped``    — ``class_id`` is a palette class name; solid classes enter
                  the β fit, liquid classes never do.
- ``unmapped``  — no corresponding MeData class; excluded, never reassigned
                  (Req 1.4). ``class_id`` must be null.
- ``ambiguous`` — the category does not state the cooking method a split
                  class needs (generic rice / potato / bread); excluded from
                  BOTH sides, never silently assigned (Req 1.3). ``class_id``
                  must be null.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

STATUS_MAPPED = "mapped"
STATUS_UNMAPPED = "unmapped"
STATUS_AMBIGUOUS = "ambiguous"
_VALID_STATUSES = frozenset({STATUS_MAPPED, STATUS_UNMAPPED, STATUS_AMBIGUOUS})

# Curated-only builds record this sentinel; builds against a categories
# enumeration record its SHA-256 (build_mapping.categories_digest).
CURATED_ONLY_SOURCE = "curated_rules_only"

_HERE = Path(__file__).resolve().parent
_REPO_ROOT = _HERE.parents[1]

DEFAULT_ARTIFACT = _HERE / "mapping_metafood3d_to_palette.json"
DEFAULT_CLASS_PALETTE_SWIFT = (
    _REPO_ROOT / "MedataCore" / "Sources" / "Segmentation" / "ClassPalette.swift"
)

# Decision 15: parse the live palette declaration, never the v1Standard
# retained for the persisted-meal migration (same marker-scoping pattern as
# tools/food_db/generate.py's palette lock).
PALETTE_MARKER = "v2Standard"


class MappingError(Exception):
    """Raised when the mapping artifact is invalid or was built against a
    different palette content (Decision 15 content lock)."""


def normalise_category(name: str) -> str:
    """Canonical snake_case form for a MetaFood3D category name.

    The dataset's exact folder capitalisation/separators are not publicly
    documented, so both the curated rules and the ingest-time enumeration
    are compared in this normalised space to keep cosmetic naming
    differences from silently unmapping a category."""
    return re.sub(r"[\s_-]+", "_", name.strip().lower()).strip("_")


@dataclass(frozen=True)
class PaletteClasses:
    """Ordered palette content parsed from ClassPalette.swift v2Standard."""
    food: list[str]
    liquid: list[str]

    @property
    def class_list(self) -> list[str]:
        # Canonical order: foodClasses then liquidClasses, declaration
        # order, sentinels excluded (same shape as the DB bake lock).
        return self.food + self.liquid


def parse_palette(
    class_palette_swift: str | Path = DEFAULT_CLASS_PALETTE_SWIFT,
) -> PaletteClasses:
    """Regex-read the ordered class lists from ClassPalette.swift's
    ``v2Standard`` declaration. Fails loudly if the palette cannot be
    parsed or the marker is absent."""
    path = Path(class_palette_swift)
    try:
        text = path.read_text()
    except OSError as exc:
        raise MappingError(f"could not read ClassPalette.swift at {path}: {exc}")

    marker = text.find(PALETTE_MARKER)
    if marker < 0:
        raise MappingError(f"no {PALETTE_MARKER} palette found in {path}")
    body = text[marker:]

    def class_array(name: str) -> list[str]:
        m = re.search(rf"{name}:\s*\[(.*?)\]", body, re.S)
        if not m:
            raise MappingError(f"could not parse {name} from {path}")
        classes = re.findall(r'"([^"]+)"', m.group(1))
        if not classes:
            raise MappingError(f"{name} parsed empty from {path}")
        return classes

    return PaletteClasses(food=class_array("foodClasses"),
                          liquid=class_array("liquidClasses"))


@dataclass(frozen=True)
class MappingEntry:
    category: str
    class_id: str | None
    status: str
    ambiguous_between: tuple[str, ...] = ()


@dataclass(frozen=True)
class Mapping:
    palette_class_list: list[str]
    categories_source: str
    entries: dict[str, MappingEntry] = field(default_factory=dict)

    def class_for(self, category: str) -> str | None:
        """Palette class for a (normalised) category, or None when the
        category is unmapped, ambiguous, or unknown — excluded, never
        reassigned (Req 1.3/1.4)."""
        entry = self.entries.get(normalise_category(category))
        if entry is None or entry.status != STATUS_MAPPED:
            return None
        return entry.class_id


def load_mapping(
    artifact_path: str | Path,
    *,
    expected_palette_class_list: list[str],
) -> Mapping:
    """Load and validate the mapping artifact, failing loudly when it was
    built against a different palette content (Decision 15)."""
    path = Path(artifact_path)
    try:
        raw = json.loads(path.read_text())
    except OSError as exc:
        raise MappingError(f"mapping artifact not readable at {path}: {exc}")
    except json.JSONDecodeError as exc:
        raise MappingError(f"mapping artifact at {path} is not valid JSON: {exc}")

    for key in ("palette_class_list", "categories_source", "mappings"):
        if key not in raw:
            raise MappingError(f"mapping artifact {path} missing key '{key}'")

    palette_class_list = list(raw["palette_class_list"])
    if palette_class_list != list(expected_palette_class_list):
        raise MappingError(
            f"mapping artifact {path} was built against a different palette "
            f"content (Decision 15 — the artifact locks v2Standard content, "
            f"and the version label alone cannot detect drift).\n"
            f"  artifact: {palette_class_list}\n"
            f"  current:  {list(expected_palette_class_list)}"
        )

    palette_set = set(palette_class_list)
    entries: dict[str, MappingEntry] = {}
    for item in raw["mappings"]:
        category = item.get("category")
        if not category:
            raise MappingError(f"mapping entry missing category: {item}")
        category = normalise_category(category)
        if category in entries:
            raise MappingError(f"duplicate mapping entry for {category}")

        status = item.get("status")
        if status not in _VALID_STATUSES:
            raise MappingError(
                f"mapping entry {category} has unknown status {status!r}; "
                f"expected one of {sorted(_VALID_STATUSES)}"
            )

        class_id = item.get("class_id")
        if status == STATUS_MAPPED:
            if class_id not in palette_set:
                raise MappingError(
                    f"mapping entry {category} maps to {class_id!r}, which "
                    f"is not a palette class (Req 1.3 — never reassign)"
                )
        elif class_id is not None:
            raise MappingError(
                f"mapping entry {category} has status {status} but carries "
                f"class_id {class_id!r}; excluded categories must not be "
                f"assigned (Req 1.3/1.4)"
            )

        entries[category] = MappingEntry(
            category=category,
            class_id=class_id,
            status=status,
            ambiguous_between=tuple(item.get("ambiguous_between", ())),
        )

    return Mapping(
        palette_class_list=palette_class_list,
        categories_source=raw["categories_source"],
        entries=entries,
    )

"""N5k ingredient -> palette class mapping artifact loader (Req 2.1-2.5).

The artifact (``mapping_n5k_to_palette.json``, built by ``build_mapping.py``)
is versioned against two inputs and this loader fails loudly if either does
not match what it was built against (Req 2.5):

- ``palette_class_list`` — the palette CONTENT (ordered class list: the 24
  solid classes in ``generate.py`` FOOD_DATA channel order, then the 8 coarse
  liquid classes). Decision 23 keeps the ``"v1"`` label when the palette
  changes, so the label alone cannot detect drift — content is the key.
- ``n5k_metadata_version`` — SHA-256 of ``ingredients_metadata.csv``.

Statuses form a closed vocabulary:

- ``mapped``    — ``class_id`` is a palette class (solid enters the β fit;
                  liquid class ids exist so routing can detect liquid-bearing
                  plates, Req 4.7 — they never enter the fit).
- ``unmapped``  — no corresponding MeData class; excluded, never reassigned
                  (Req 2.3). ``class_id`` must be null.
- ``ambiguous`` — the N5k taxonomy does not distinguish a MeData class pair
                  (generic rice / potatoes / bread); excluded from BOTH sides,
                  never silently assigned (Req 2.4). ``class_id`` must be null.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from pathlib import Path

STATUS_MAPPED = "mapped"
STATUS_UNMAPPED = "unmapped"
STATUS_AMBIGUOUS = "ambiguous"
_VALID_STATUSES = frozenset({STATUS_MAPPED, STATUS_UNMAPPED, STATUS_AMBIGUOUS})

_HERE = Path(__file__).resolve().parent
_REPO_ROOT = _HERE.parents[1]

DEFAULT_ARTIFACT = _HERE / "mapping_n5k_to_palette.json"
DEFAULT_CLASS_PALETTE_SWIFT = (
    _REPO_ROOT / "MedataCore" / "Sources" / "Segmentation" / "ClassPalette.swift"
)


class MappingError(Exception):
    """Raised when the mapping artifact is invalid or was built against a
    different palette content / ingredient-metadata version (Req 2.5)."""


def canonical_ingredient_id(numeric_id: int) -> str:
    """The ``ingr_%010d`` form dish_metadata_cafe*.csv rows use."""
    return f"ingr_{numeric_id:010d}"


def metadata_version(ingredients_csv: str | Path) -> str:
    """SHA-256 hex of the ingredient-metadata CSV bytes — the operational
    ingredient-metadata version (the GCS bucket is unversioned, Req 1.4)."""
    return hashlib.sha256(Path(ingredients_csv).read_bytes()).hexdigest()


@dataclass(frozen=True)
class PaletteClasses:
    """Ordered palette content parsed from ClassPalette.swift v1Standard."""
    food: list[str]
    liquid: list[str]

    @property
    def class_list(self) -> list[str]:
        # Canonical order per design §DB bake: foodClasses then liquidClasses,
        # declaration order, sentinels excluded.
        return self.food + self.liquid


def parse_palette(
    class_palette_swift: str | Path = DEFAULT_CLASS_PALETTE_SWIFT,
) -> PaletteClasses:
    """Regex-read the ordered class lists from ClassPalette.swift's
    ``v1Standard`` (the same source-of-truth pattern generate.py's palette
    lock uses). Fails loudly if the palette cannot be parsed."""
    path = Path(class_palette_swift)
    try:
        text = path.read_text()
    except OSError as exc:
        raise MappingError(f"could not read ClassPalette.swift at {path}: {exc}")

    marker = text.find("v1Standard")
    if marker < 0:
        raise MappingError(f"no v1Standard palette found in {path}")
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
    n5k_ingredient_id: str
    class_id: str | None
    status: str
    n5k_ingredient_name: str = ""


@dataclass(frozen=True)
class Mapping:
    palette_class_list: list[str]
    n5k_metadata_version: str
    entries: dict[str, MappingEntry] = field(default_factory=dict)

    def class_for(self, ingredient_id: str) -> str | None:
        """Palette class for an ingredient, or None when the ingredient is
        unmapped, ambiguous, or unknown — excluded, never reassigned."""
        entry = self.entries.get(ingredient_id)
        if entry is None or entry.status != STATUS_MAPPED:
            return None
        return entry.class_id


def load_mapping(
    artifact_path: str | Path,
    *,
    expected_palette_class_list: list[str],
    expected_metadata_version: str,
) -> Mapping:
    """Load and validate the mapping artifact, failing loudly (Req 2.5) when
    it was built against a different palette content or metadata version."""
    path = Path(artifact_path)
    try:
        raw = json.loads(path.read_text())
    except OSError as exc:
        raise MappingError(f"mapping artifact not readable at {path}: {exc}")
    except json.JSONDecodeError as exc:
        raise MappingError(f"mapping artifact at {path} is not valid JSON: {exc}")

    for key in ("palette_class_list", "n5k_metadata_version", "mappings"):
        if key not in raw:
            raise MappingError(f"mapping artifact {path} missing key '{key}'")

    palette_class_list = list(raw["palette_class_list"])
    if palette_class_list != list(expected_palette_class_list):
        raise MappingError(
            f"mapping artifact {path} was built against a different palette "
            f"content (Req 2.5 / Decision 23 — the 'v1' label does not change "
            f"when the palette does).\n  artifact: {palette_class_list}\n"
            f"  current:  {list(expected_palette_class_list)}"
        )

    artifact_version = raw["n5k_metadata_version"]
    if artifact_version != expected_metadata_version:
        raise MappingError(
            f"mapping artifact {path} was built against ingredient-metadata "
            f"version {artifact_version}, but the current version is "
            f"{expected_metadata_version} (Req 2.5)."
        )

    palette_set = set(palette_class_list)
    entries: dict[str, MappingEntry] = {}
    for item in raw["mappings"]:
        ingredient_id = item.get("n5k_ingredient_id")
        if not ingredient_id:
            raise MappingError(f"mapping entry missing n5k_ingredient_id: {item}")
        if ingredient_id in entries:
            raise MappingError(f"duplicate mapping entry for {ingredient_id}")

        status = item.get("status")
        if status not in _VALID_STATUSES:
            raise MappingError(
                f"mapping entry {ingredient_id} has unknown status "
                f"{status!r}; expected one of {sorted(_VALID_STATUSES)}"
            )

        class_id = item.get("class_id")
        if status == STATUS_MAPPED:
            if class_id not in palette_set:
                raise MappingError(
                    f"mapping entry {ingredient_id} maps to {class_id!r}, "
                    f"which is not a palette class (Req 2.3 — never reassign)"
                )
        elif class_id is not None:
            raise MappingError(
                f"mapping entry {ingredient_id} has status {status} but "
                f"carries class_id {class_id!r}; excluded ingredients must "
                f"not be assigned (Req 2.3/2.4)"
            )

        entries[ingredient_id] = MappingEntry(
            n5k_ingredient_id=ingredient_id,
            class_id=class_id,
            status=status,
            n5k_ingredient_name=item.get("n5k_ingredient_name", ""),
        )

    return Mapping(
        palette_class_list=palette_class_list,
        n5k_metadata_version=artifact_version,
        entries=entries,
    )

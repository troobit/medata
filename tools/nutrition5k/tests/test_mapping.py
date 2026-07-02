"""Tests for the N5k ingredient -> palette mapping artifact and its loader.

Req 2.1-2.5 (specs/estimation/nutrition5k-calibration): the artifact is keyed
to the palette CONTENT (ordered class list) and the ingredient-metadata
version, not the static "v1" label (Decision 23). Unmapped ingredients are
excluded, never reassigned; pair-ambiguous ingredients (generic rice /
potatoes / bread) are recorded status=ambiguous and excluded from both sides.

The checked-in artifact tests run against the committed JSON + the committed
ClassPalette.swift / generate.py FOOD_DATA — no gitignored N5k data needed.
"""

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

import pytest

import mapping

_REPO_ROOT = Path(__file__).resolve().parents[3]
_GENERATE_PY = _REPO_ROOT / "tools" / "food_db" / "generate.py"

EXPECTED_SOLIDS = [
    "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
    "potato_boiled", "potato_mashed", "chips_fries", "chicken", "beef",
    "pork", "fish_white", "egg", "cheese", "salad_leaves",
    "broccoli", "carrot", "peas", "beans_baked", "lentils",
    "apple", "banana", "tomato", "mixed_vegetables",
]
EXPECTED_LIQUIDS = [
    "water", "coffee", "tea", "milk", "fruit_juice", "soup", "beer", "wine",
]

# The carb-priority staples with an unambiguous N5k ingredient (Req 2.2 —
# "where corresponding N5k ingredients exist"). potato_boiled has none:
# N5k's "potatoes" (5) / "red potatoes" (432) do not state the preparation,
# so they are pair-ambiguous (Req 2.4) and "roasted"/"baked potatoes" are a
# different preparation entirely.
STAPLE_INGREDIENTS = {
    "white_rice": "ingr_0000000026",       # white rice
    "brown_rice": "ingr_0000000023",       # brown rice
    "pasta": "ingr_0000000074",            # pasta
    "bread_white": "ingr_0000000334",      # white bread
    "bread_wholemeal": "ingr_0000000169",  # whole wheat bread
    "potato_mashed": "ingr_0000000254",    # mashed potatoes
    "chips_fries": "ingr_0000000356",      # french fries
}

# Pair-ambiguous ingredients: the N5k taxonomy does not distinguish the
# MeData class pair (Req 2.4), so these are recorded ambiguous and excluded
# from BOTH sides.
AMBIGUOUS_INGREDIENTS = {
    "ingr_0000000482": ("white_rice", "brown_rice"),          # "rice"
    "ingr_0000000005": ("potato_boiled", "potato_mashed"),    # "potatoes"
    "ingr_0000000019": ("bread_white", "bread_wholemeal"),    # "bread"
}

# One mapped N5k ingredient per liquid class — routing (Req 4.7) can only
# detect liquid-bearing plates if liquid ingredients map to liquid class ids.
LIQUID_INGREDIENTS = {
    "water": "ingr_0000000321",
    "coffee": "ingr_0000000384",
    "tea": "ingr_0000000490",
    "milk": "ingr_0000000502",
    "fruit_juice": "ingr_0000000498",  # orange juice
    "soup": "ingr_0000000326",         # chicken soup
    "beer": "ingr_0000000278",
    "wine": "ingr_0000000092",
}


def _food_data_class_ids():
    spec = importlib.util.spec_from_file_location("food_db_generate", _GENERATE_PY)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return [row[0] for row in module.FOOD_DATA]


@pytest.fixture(scope="session")
def palette():
    return mapping.parse_palette()


@pytest.fixture(scope="session")
def artifact(palette):
    return mapping.load_mapping(
        mapping.DEFAULT_ARTIFACT,
        expected_palette_class_list=palette.class_list,
        expected_metadata_version=_committed_metadata_version(),
    )


def _committed_metadata_version():
    with open(mapping.DEFAULT_ARTIFACT) as fh:
        return json.load(fh)["n5k_metadata_version"]


def _write_artifact(tmp_path, *, palette_class_list, metadata_version,
                    mappings):
    path = tmp_path / "mapping.json"
    path.write_text(json.dumps({
        "palette_class_list": palette_class_list,
        "n5k_metadata_version": metadata_version,
        "mappings": mappings,
    }))
    return path


# --------------------------------------------------------------------------- #
# Palette parsing (Req 2.1 — keyed to the current ClassPalette content).
# --------------------------------------------------------------------------- #
class TestParsePalette:
    def test_parses_solids_and_liquids_in_declaration_order(self, palette):
        assert palette.food == EXPECTED_SOLIDS
        assert palette.liquid == EXPECTED_LIQUIDS

    def test_class_list_is_solids_then_liquids(self, palette):
        assert palette.class_list == EXPECTED_SOLIDS + EXPECTED_LIQUIDS

    def test_unparsable_swift_fails_loudly(self, tmp_path):
        bogus = tmp_path / "ClassPalette.swift"
        bogus.write_text("no palette here")
        with pytest.raises(mapping.MappingError):
            mapping.parse_palette(bogus)


# --------------------------------------------------------------------------- #
# Artifact content (Req 2.1/2.2/2.4 — against the committed artifact).
# --------------------------------------------------------------------------- #
class TestArtifactContent:
    def test_palette_class_list_preserves_food_data_channel_order(self, artifact):
        # Req 2.1: solid class ids in FOOD_DATA channel order, then liquids.
        assert artifact.palette_class_list[:24] == _food_data_class_ids()
        assert artifact.palette_class_list == EXPECTED_SOLIDS + EXPECTED_LIQUIDS

    def test_staples_mapped_where_n5k_ingredients_exist(self, artifact):
        for class_id, ingredient_id in STAPLE_INGREDIENTS.items():
            assert artifact.class_for(ingredient_id) == class_id, (
                f"{ingredient_id} should map to staple {class_id}"
            )

    def test_potato_boiled_has_no_unambiguous_ingredient(self, artifact):
        # Documented gap: no N5k ingredient states the boiled preparation.
        mapped_classes = {
            entry.class_id for entry in artifact.entries.values()
            if entry.status == mapping.STATUS_MAPPED
        }
        assert "potato_boiled" not in mapped_classes

    def test_ambiguous_pairs_recorded_and_excluded_from_both_sides(self, artifact):
        for ingredient_id, pair in AMBIGUOUS_INGREDIENTS.items():
            entry = artifact.entries[ingredient_id]
            assert entry.status == mapping.STATUS_AMBIGUOUS
            assert entry.class_id is None
            # Excluded from both sides: the ambiguous ingredient must not be
            # the source of either pair member's mapping.
            assert artifact.class_for(ingredient_id) is None
            for side in pair:
                mapped_from = [
                    iid for iid, e in artifact.entries.items()
                    if e.class_id == side
                ]
                assert ingredient_id not in mapped_from

    def test_every_liquid_class_has_a_mapped_ingredient(self, artifact, palette):
        for class_id, ingredient_id in LIQUID_INGREDIENTS.items():
            assert class_id in palette.liquid
            assert artifact.class_for(ingredient_id) == class_id

    def test_covers_more_than_the_staple_floor(self, artifact):
        # Design §Mapping artifact: 8 staples are the floor, not the cap —
        # broad coverage feeds the mixture path.
        mapped_solid_classes = {
            e.class_id for e in artifact.entries.values()
            if e.status == mapping.STATUS_MAPPED
            and e.class_id in EXPECTED_SOLIDS
        }
        assert len(mapped_solid_classes) >= 15


# --------------------------------------------------------------------------- #
# Loader guards (Req 2.3/2.5 — fail loudly, never reassign).
# --------------------------------------------------------------------------- #
class TestLoaderGuards:
    PALETTE = EXPECTED_SOLIDS + EXPECTED_LIQUIDS

    def _load(self, path, palette_class_list=None, metadata_version="metaver"):
        return mapping.load_mapping(
            path,
            expected_palette_class_list=palette_class_list or self.PALETTE,
            expected_metadata_version=metadata_version,
        )

    def test_unmapped_ingredient_excluded(self, tmp_path):
        path = _write_artifact(
            tmp_path, palette_class_list=self.PALETTE, metadata_version="metaver",
            mappings=[{"n5k_ingredient_id": "ingr_0000000508",
                       "class_id": None, "status": "unmapped"}],
        )
        loaded = self._load(path)
        assert loaded.class_for("ingr_0000000508") is None
        assert loaded.entries["ingr_0000000508"].status == mapping.STATUS_UNMAPPED

    def test_unknown_ingredient_id_is_none(self, tmp_path):
        path = _write_artifact(
            tmp_path, palette_class_list=self.PALETTE, metadata_version="metaver",
            mappings=[],
        )
        assert self._load(path).class_for("ingr_9999999999") is None

    def test_mapped_entry_with_unknown_class_rejected(self, tmp_path):
        # Never reassigned to an unrelated/nonexistent class (Req 2.3).
        path = _write_artifact(
            tmp_path, palette_class_list=self.PALETTE, metadata_version="metaver",
            mappings=[{"n5k_ingredient_id": "ingr_0000000001",
                       "class_id": "not_a_class", "status": "mapped"}],
        )
        with pytest.raises(mapping.MappingError):
            self._load(path)

    def test_unmapped_entry_carrying_class_id_rejected(self, tmp_path):
        path = _write_artifact(
            tmp_path, palette_class_list=self.PALETTE, metadata_version="metaver",
            mappings=[{"n5k_ingredient_id": "ingr_0000000001",
                       "class_id": "white_rice", "status": "unmapped"}],
        )
        with pytest.raises(mapping.MappingError):
            self._load(path)

    def test_ambiguous_entry_carrying_class_id_rejected(self, tmp_path):
        path = _write_artifact(
            tmp_path, palette_class_list=self.PALETTE, metadata_version="metaver",
            mappings=[{"n5k_ingredient_id": "ingr_0000000019",
                       "class_id": "bread_white", "status": "ambiguous"}],
        )
        with pytest.raises(mapping.MappingError):
            self._load(path)

    def test_unknown_status_rejected(self, tmp_path):
        path = _write_artifact(
            tmp_path, palette_class_list=self.PALETTE, metadata_version="metaver",
            mappings=[{"n5k_ingredient_id": "ingr_0000000001",
                       "class_id": None, "status": "maybe"}],
        )
        with pytest.raises(mapping.MappingError):
            self._load(path)

    def test_duplicate_ingredient_id_rejected(self, tmp_path):
        entry = {"n5k_ingredient_id": "ingr_0000000001",
                 "class_id": None, "status": "unmapped"}
        path = _write_artifact(
            tmp_path, palette_class_list=self.PALETTE, metadata_version="metaver",
            mappings=[entry, dict(entry)],
        )
        with pytest.raises(mapping.MappingError):
            self._load(path)

    def test_palette_content_mismatch_fails_loudly(self, tmp_path):
        # Req 2.5 / Decision 23: the "v1" label no longer changes, so a stale
        # artifact must fail on CONTENT — here a reordered class list.
        reordered = list(self.PALETTE)
        reordered[0], reordered[1] = reordered[1], reordered[0]
        path = _write_artifact(
            tmp_path, palette_class_list=reordered, metadata_version="metaver",
            mappings=[],
        )
        with pytest.raises(mapping.MappingError, match="palette"):
            self._load(path)

    def test_metadata_version_mismatch_fails_loudly(self, tmp_path):
        path = _write_artifact(
            tmp_path, palette_class_list=self.PALETTE, metadata_version="old-version",
            mappings=[],
        )
        with pytest.raises(mapping.MappingError, match="metadata"):
            self._load(path, metadata_version="new-version")


# --------------------------------------------------------------------------- #
# Helpers.
# --------------------------------------------------------------------------- #
class TestHelpers:
    def test_metadata_version_is_sha256_of_csv(self, tmp_path):
        csv = tmp_path / "ingredients_metadata.csv"
        csv.write_bytes(b"ingr,id\nrice,1\n")
        expected = hashlib.sha256(b"ingr,id\nrice,1\n").hexdigest()
        assert mapping.metadata_version(csv) == expected

    def test_canonical_ingredient_id_matches_dish_metadata_format(self):
        assert mapping.canonical_ingredient_id(26) == "ingr_0000000026"
        assert mapping.canonical_ingredient_id(508) == "ingr_0000000508"

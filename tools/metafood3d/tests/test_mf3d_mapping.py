"""Tests for the MetaFood3D category -> palette mapping artifact and loader.

Req 1.3/1.4 (specs/estimation/cross-dataset-calibration), as amended by
Decision 15: the artifact is keyed to the palette **v2** CONTENT (ordered
class list parsed from ClassPalette.swift ``v2Standard``), and mapped
categories target palette class NAMES — β is name-keyed end-to-end, so the
content lock (not channel ordering) is what the artifact preserves.

Since Decision 20 the rules are written against the REAL 108-category
enumeration (derived from the v2 nutrition workbook by
derive_metadata.py), and the committed artifact is built in enumerated
mode — ``categories_source`` records the enumeration's SHA-256 and all
108 categories are recorded. The raw dataset stays out of the repo
(Req 1.2); these tests pin the committed artifact's shape without it.

A category whose cooking method is ambiguous for a split class (generic
``rice``, ``yeast_bread``) is recorded status=ambiguous and excluded from
BOTH sides, never guessed (Req 1.3).
"""

import hashlib
import json
from pathlib import Path

import pytest

from mf3d_testkit import load_tool

mapping = load_tool("mapping")
build_mapping = load_tool("build_mapping")

_REPO_ROOT = Path(__file__).resolve().parents[3]
_CLASS_PALETTE_SWIFT = (
    _REPO_ROOT / "MedataCore" / "Sources" / "Segmentation" / "ClassPalette.swift"
)

# Palette v2 content (Decision 15): 25 solids (cereal appended at index 24)
# then 8 liquids; sentinels excluded from the content list.
EXPECTED_SOLIDS = [
    "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
    "potato_boiled", "potato_mashed", "chips_fries", "chicken", "beef",
    "pork", "fish_white", "egg", "cheese", "salad_leaves",
    "broccoli", "carrot", "peas", "beans_baked", "lentils",
    "apple", "banana", "tomato", "mixed_vegetables", "cereal",
]
EXPECTED_LIQUIDS = [
    "water", "coffee", "tea", "milk", "fruit_juice", "soup", "beer", "wine",
]


@pytest.fixture(scope="module")
def palette():
    return mapping.parse_palette(_CLASS_PALETTE_SWIFT)


@pytest.fixture()
def artifact(tmp_path, palette):
    """Curated-rules-only build (no categories enumeration on disk)."""
    out = tmp_path / "mapping_metafood3d_to_palette.json"
    build_mapping.build(
        categories=None,
        class_palette_swift=_CLASS_PALETTE_SWIFT,
        out_path=out,
    )
    return json.loads(out.read_text())


def _write_artifact(tmp_path, *, palette_class_list, mappings,
                    categories_source="curated_rules_only"):
    path = tmp_path / "artifact.json"
    path.write_text(json.dumps({
        "palette_class_list": palette_class_list,
        "categories_source": categories_source,
        "mappings": mappings,
    }))
    return path


class TestParsePalette:
    def test_parses_v2_solids_and_liquids_in_declaration_order(self, palette):
        assert palette.food == EXPECTED_SOLIDS
        assert palette.liquid == EXPECTED_LIQUIDS

    def test_reads_v2standard_not_the_retained_v1_declaration(self, palette):
        # v1Standard is retained in ClassPalette.swift for the persisted-meal
        # migration; the parse must scope to v2Standard (Decision 15).
        assert "cereal" in palette.food
        assert palette.food.index("cereal") == 24

    def test_class_list_is_solids_then_liquids(self, palette):
        assert palette.class_list == EXPECTED_SOLIDS + EXPECTED_LIQUIDS

    def test_unparsable_swift_fails_loudly(self, tmp_path):
        bogus = tmp_path / "ClassPalette.swift"
        bogus.write_text("// no palette here")
        with pytest.raises(mapping.MappingError):
            mapping.parse_palette(bogus)


class TestNormalisation:
    @pytest.mark.parametrize("raw,expected", [
        ("Mashed Potatoes", "mashed_potatoes"),
        ("  White-Rice ", "white_rice"),
        ("french  fries", "french_fries"),
        ("PBJ_Sandwich", "pbj_sandwich"),
    ])
    def test_categories_normalise_to_snake_case(self, raw, expected):
        assert mapping.normalise_category(raw) == expected


class TestBuildArtifact:
    def test_palette_class_list_is_the_live_v2_content_in_order(self, artifact):
        # Decision 15: the content lock targets v2Standard.
        assert artifact["palette_class_list"] == EXPECTED_SOLIDS + EXPECTED_LIQUIDS

    def test_every_mapped_category_targets_a_valid_v2_class_name(self, artifact):
        palette_set = set(artifact["palette_class_list"])
        mapped = [e for e in artifact["mappings"] if e["status"] == "mapped"]
        assert mapped, "curated rules produced no mapped categories"
        for entry in mapped:
            assert entry["class_id"] in palette_set, entry

    def test_ambiguous_cooking_method_categories_excluded_not_guessed(self, artifact):
        by_cat = {e["category"]: e for e in artifact["mappings"]}
        # The real taxonomy's generic categories that cannot split for us.
        expected_pairs = {
            "rice": ["white_rice", "brown_rice"],
            "yeast_bread": ["bread_white", "bread_wholemeal"],
        }
        for cat, pair in expected_pairs.items():
            entry = by_cat[cat]
            assert entry["status"] == "ambiguous"
            assert entry["class_id"] is None
            assert entry["ambiguous_between"] == pair

    def test_stated_preparations_map_unambiguously(self, artifact):
        by_cat = {e["category"]: e for e in artifact["mappings"]}
        assert by_cat["french_fry"]["class_id"] == "chips_fries"
        assert by_cat["mashed_potato"]["class_id"] == "potato_mashed"

    def test_real_enumeration_coverage_is_exactly_eleven_classes(self, artifact):
        # Decision 20: the real dataset covers LESS than the blind rules
        # hoped. No cereal-type category exists (Decision 15's cereal
        # reachability is void), no plain pasta (only pasta_mixed_dishes,
        # composite), no lentils; rice and bread appear only as
        # method-ambiguous generics. This pins the honest coverage.
        mapped_classes = {e["class_id"] for e in artifact["mappings"]
                          if e["status"] == "mapped"}
        assert mapped_classes == {
            "apple", "banana", "beef", "broccoli", "carrot", "chicken",
            "chips_fries", "egg", "pork", "potato_mashed", "tomato",
        }
        for absent in ("cereal", "pasta", "lentils", "white_rice",
                       "bread_white"):
            assert absent not in mapped_classes, absent

    def test_unmapped_categories_counted(self, tmp_path):
        # Req 1.4: categories with no palette mapping are excluded and the
        # excluded count is recorded.
        cats = sorted(set(build_mapping.MAPPED_RULES)
                      | set(build_mapping.AMBIGUOUS_RULES)
                      | {"pizza", "sushi", "nachos"})
        out = tmp_path / "artifact.json"
        result = build_mapping.build(
            categories=cats,
            class_palette_swift=_CLASS_PALETTE_SWIFT,
            out_path=out,
        )
        artifact = json.loads(out.read_text())
        unmapped = [e for e in artifact["mappings"] if e["status"] == "unmapped"]
        assert {e["category"] for e in unmapped} == {"pizza", "sushi", "nachos"}
        for entry in unmapped:
            assert entry["class_id"] is None
        assert result["counts"]["unmapped"] == 3

    def test_categories_source_records_the_enumeration(self, tmp_path):
        cats = sorted(set(build_mapping.MAPPED_RULES)
                      | set(build_mapping.AMBIGUOUS_RULES))
        out = tmp_path / "artifact.json"
        build_mapping.build(categories=cats,
                            class_palette_swift=_CLASS_PALETTE_SWIFT,
                            out_path=out)
        artifact = json.loads(out.read_text())
        digest = hashlib.sha256(
            "\n".join(sorted(mapping.normalise_category(c) for c in cats))
            .encode()).hexdigest()
        assert artifact["categories_source"] == digest

    def test_curated_only_build_records_curated_source(self, artifact):
        assert artifact["categories_source"] == "curated_rules_only"

    def test_rule_targeting_non_palette_class_aborts(self, tmp_path, monkeypatch):
        monkeypatch.setitem(build_mapping.MAPPED_RULES, "gruel", "not_a_class")
        with pytest.raises(SystemExit):
            build_mapping.build(categories=None,
                                class_palette_swift=_CLASS_PALETTE_SWIFT,
                                out_path=tmp_path / "artifact.json")

    def test_stale_rule_aborts_when_categories_supplied(self, tmp_path):
        # A rule naming a category the enumeration lacks is a curation typo
        # (n5k stale-check semantics).
        with pytest.raises(SystemExit):
            build_mapping.build(categories=["pizza"],
                                class_palette_swift=_CLASS_PALETTE_SWIFT,
                                out_path=tmp_path / "artifact.json")


class TestCommittedArtifact:
    def test_committed_artifact_loads_against_the_live_palette(self, palette):
        loaded = mapping.load_mapping(
            mapping.DEFAULT_ARTIFACT,
            expected_palette_class_list=palette.class_list,
        )
        assert loaded.palette_class_list == palette.class_list

    def test_committed_artifact_is_enumerated_not_curated_only(self):
        # Decision 20: the committed artifact is built against the real
        # 108-category enumeration; categories_source is its SHA-256, and
        # every snapshot category is recorded (unmapped included). The
        # enumeration file itself is gitignored NC-adjacent data, so this
        # pins shape and counts, not the digest value.
        doc = json.loads(mapping.DEFAULT_ARTIFACT.read_text())
        source = doc["categories_source"]
        assert source != "curated_rules_only"
        assert len(source) == 64 and set(source) <= set("0123456789abcdef")
        counts: dict[str, int] = {}
        for e in doc["mappings"]:
            counts[e["status"]] = counts.get(e["status"], 0) + 1
        assert len(doc["mappings"]) == 108
        assert counts == {"mapped": 13, "ambiguous": 2, "unmapped": 93}


class TestLoaderGuards:
    def _entry(self, category="pizza", class_id=None, status="unmapped", **kw):
        return {"category": category, "class_id": class_id,
                "status": status, **kw}

    def test_palette_content_mismatch_fails_loudly(self, tmp_path, palette):
        # An artifact built against the superseded v1 content (no cereal)
        # must be rejected (Decision 15).
        v1_list = [c for c in palette.class_list if c != "cereal"]
        path = _write_artifact(tmp_path, palette_class_list=v1_list,
                               mappings=[])
        with pytest.raises(mapping.MappingError, match="palette"):
            mapping.load_mapping(
                path, expected_palette_class_list=palette.class_list)

    def test_mapped_entry_with_unknown_class_rejected(self, tmp_path, palette):
        path = _write_artifact(
            tmp_path, palette_class_list=palette.class_list,
            mappings=[self._entry(class_id="not_a_class", status="mapped")])
        with pytest.raises(mapping.MappingError):
            mapping.load_mapping(
                path, expected_palette_class_list=palette.class_list)

    def test_unmapped_entry_carrying_class_id_rejected(self, tmp_path, palette):
        path = _write_artifact(
            tmp_path, palette_class_list=palette.class_list,
            mappings=[self._entry(class_id="pasta", status="unmapped")])
        with pytest.raises(mapping.MappingError):
            mapping.load_mapping(
                path, expected_palette_class_list=palette.class_list)

    def test_ambiguous_entry_carrying_class_id_rejected(self, tmp_path, palette):
        path = _write_artifact(
            tmp_path, palette_class_list=palette.class_list,
            mappings=[self._entry(class_id="pasta", status="ambiguous",
                                  ambiguous_between=["a", "b"])])
        with pytest.raises(mapping.MappingError):
            mapping.load_mapping(
                path, expected_palette_class_list=palette.class_list)

    def test_unknown_status_rejected(self, tmp_path, palette):
        path = _write_artifact(
            tmp_path, palette_class_list=palette.class_list,
            mappings=[self._entry(status="maybe")])
        with pytest.raises(mapping.MappingError):
            mapping.load_mapping(
                path, expected_palette_class_list=palette.class_list)

    def test_duplicate_category_rejected(self, tmp_path, palette):
        path = _write_artifact(
            tmp_path, palette_class_list=palette.class_list,
            mappings=[self._entry(), self._entry()])
        with pytest.raises(mapping.MappingError):
            mapping.load_mapping(
                path, expected_palette_class_list=palette.class_list)

    def test_class_for_excluded_and_unknown_is_none(self, tmp_path, palette):
        path = _write_artifact(
            tmp_path, palette_class_list=palette.class_list,
            mappings=[
                self._entry(category="pizza", status="unmapped"),
                self._entry(category="rice", status="ambiguous",
                            ambiguous_between=["white_rice", "brown_rice"]),
                self._entry(category="pasta", class_id="pasta",
                            status="mapped"),
            ])
        loaded = mapping.load_mapping(
            path, expected_palette_class_list=palette.class_list)
        assert loaded.class_for("pizza") is None
        assert loaded.class_for("rice") is None
        assert loaded.class_for("never_seen") is None
        assert loaded.class_for("pasta") == "pasta"

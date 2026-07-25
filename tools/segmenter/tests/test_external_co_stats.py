"""External co-occurrence stats builder tests (snaq-parity task 21, Req 6.1).

``build_external_co_stats.py`` ingests a Recipe1M+-style ingredient corpus,
maps ingredients onto the 35-class palette via the committed
``ingredient_mapping_recipe1m_v1.json`` (reviewable, like the class mapping),
and emits the ``co_stats.v2`` shape amended with ``source: "recipe1m"``,
``split_seed: null``, the ingredient-mapping SHA-256, and the palette-coverage
lists (Decision 13). ``loss_config.load_co_stats`` accepts a null seed ONLY
when the source is external; palette identity (``class_mapping_sha256``),
channel count, and the food-channels-only rule (Decision 20) stay enforced.

Everything here is pure stdlib + json — torch-free (the loss_config pattern).
The fixture corpus lives under ``tests/fixtures``; running the tool on a real
Recipe1M+ corpus is human-gated (prerequisites.md).
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

import build_external_co_stats as bex
import lineage
import loss_config
import train  # torch-free import: heavy deps are lazy

_TOOLS = Path(__file__).resolve().parent.parent
FIXTURE_CORPUS = Path(__file__).resolve().parent / "fixtures" / "recipe_corpus_fixture_v1.json"
INGREDIENT_MAPPING = _TOOLS / "ingredient_mapping_recipe1m_v1.json"
CLASS_MAPPING = _TOOLS / "class_mapping_foodseg103_v1.json"

# Palette facts (class_mapping_foodseg103_v1.json, palette v2 — MD-29).
CHANNEL_COUNT = 36
SPECIALS = [33, 34, 35]
WHITE_RICE, CHICKEN, CARROT = 0, 8, 16


def _class_mapping() -> dict:
    return json.loads(CLASS_MAPPING.read_text())


def _food_names() -> list[str]:
    d = _class_mapping()
    specials = set(d["special_channels"])
    channels = sorted(d["target_channels"], key=lambda c: c["index"])
    return [c["name"] for c in channels if c["name"] not in specials]


# ── The committed ingredient mapping is reviewable and palette-complete ─────────

def test_ingredient_mapping_is_committed_and_names_its_source():
    d = json.loads(INGREDIENT_MAPPING.read_text())
    assert d["schema"] == "ingredient_mapping_recipe1m_v1"
    assert d["source"] == "recipe1m"
    assert d["palette_version"] == "v2"
    assert d["channel_count"] == CHANNEL_COUNT


def test_ingredient_mapping_targets_food_classes_only():
    d = json.loads(INGREDIENT_MAPPING.read_text())
    foods = set(_food_names())
    targets = set(d["mappings"].values())
    assert targets <= foods  # never background/unknown_food/unsupported_liquid
    # Every food class has at least one term, so zero coverage can only come
    # from the corpus, never from the mapping by construction.
    assert targets == foods


# ── Ingredient normalisation and term matching ──────────────────────────────────

def test_normalise_strips_case_punctuation_and_quantities():
    assert bex.normalise_ingredient("2 cups White Rice, rinsed") == "2 cups white rice rinsed"


def test_longest_term_wins_and_unknown_terms_stay_unmapped():
    mappings = json.loads(INGREDIENT_MAPPING.read_text())["mappings"]
    assert bex.map_ingredient("2 cups white rice", mappings) == "white_rice"
    assert bex.map_ingredient("brown rice", mappings) == "brown_rice"
    # Longest match wins: "wholemeal bread" must not fall through to the
    # generic "bread" term.
    assert bex.map_ingredient("2 slices wholemeal bread", mappings) == "bread_wholemeal"
    # "chicken soup" is soup, not chicken (the 2-word term outranks both).
    assert bex.map_ingredient("chicken soup", mappings) == "soup"
    # "apple juice" is fruit_juice, not apple.
    assert bex.map_ingredient("apple juice", mappings) == "fruit_juice"
    # Word-boundary matching: no term for bare "rice".
    assert bex.map_ingredient("rice vinegar", mappings) is None
    assert bex.map_ingredient("salt", mappings) is None


# ── Presence / joint-presence counting (pure maths) ─────────────────────────────

def test_presence_counting_matches_the_prepare_dataset_convention():
    presence, joint = bex.count_presence(
        [{0, 8}, {0, 8}, {5}], channel_count=10, special_channel_indices=[9],
    )
    assert presence[0] == presence[8] == 2
    assert presence[5] == 1
    assert joint[0][8] == joint[8][0] == 2
    assert joint[0][0] == 2  # diagonal = presence
    assert joint[5][0] == 0


def test_special_channels_are_excluded_from_counts():
    presence, joint = bex.count_presence(
        [{0, 9}], channel_count=10, special_channel_indices=[9],
    )
    assert presence[9] == 0
    assert all(joint[9][k] == 0 for k in range(10))
    assert all(joint[k][9] == 0 for k in range(10))


# ── Full build over the committed fixture corpus ────────────────────────────────

@pytest.fixture
def fixture_stats():
    return bex.build_external_co_stats(
        bex.load_corpus(FIXTURE_CORPUS),
        json.loads(INGREDIENT_MAPPING.read_text()),
        _class_mapping(),
        ingredient_mapping_sha256=lineage.file_sha256(INGREDIENT_MAPPING),
    )


def test_output_is_co_stats_v2_with_the_external_amendments(fixture_stats):
    s = fixture_stats
    assert s["schema"] == "co_stats.v2"
    assert s["source"] == "recipe1m"
    assert s["split_seed"] is None
    assert s["channel_count"] == CHANNEL_COUNT
    assert s["special_channel_indices"] == SPECIALS
    assert s["class_mapping_sha256"] == lineage.file_sha256(CLASS_MAPPING)
    assert s["ingredient_mapping_sha256"] == lineage.file_sha256(INGREDIENT_MAPPING)
    assert s["corpus_recipes"] == 22  # 20 + the two cereal recipes (r21, r22)
    # No pixels and no split behind a recipe corpus — explicit nulls.
    assert s["pixel_counts"] is None
    assert s["train_images"] is None


def test_fixture_corpus_covers_the_whole_food_palette(fixture_stats):
    coverage = fixture_stats["palette_coverage"]
    assert coverage["with_statistics"] == _food_names()
    assert coverage["without_statistics"] == []


def test_known_co_occurrences_are_counted(fixture_stats):
    presence = fixture_stats["presence_counts"]
    joint = fixture_stats["joint_presence_counts"]
    # white rice + chicken appear together in r01 and r02 (and chicken soup in
    # r18 is SOUP, so chicken's presence stays 2).
    assert presence[WHITE_RICE] == 2
    assert presence[CHICKEN] == 2
    assert joint[WHITE_RICE][CHICKEN] == 2
    assert presence[CARROT] == 2  # r04, r10
    # Food-channels-only (Decision 20): special rows/columns stay zero.
    for c in SPECIALS:
        assert presence[c] == 0
        assert all(v == 0 for v in joint[c])


def test_unmapped_rate_is_recorded_and_below_the_default_threshold(fixture_stats):
    # salt, black pepper, olive oil, butter, gravy granules = 5 of 51 texts.
    rate = fixture_stats["unmapped_ingredient_rate"]
    assert 0.0 < rate < bex.DEFAULT_MAX_UNMAPPED_RATE


# ── Validation failures fail the tool, not the training run ─────────────────────

def test_unmapped_rate_above_threshold_fails():
    corpus = [["salt", "black pepper", "white rice"]]
    with pytest.raises(SystemExit, match="unmapped"):
        bex.build_external_co_stats(
            corpus, json.loads(INGREDIENT_MAPPING.read_text()), _class_mapping(),
            ingredient_mapping_sha256="0" * 64, max_unmapped_rate=0.5,
        )


def test_zero_coverage_classes_fail_by_name():
    corpus = [["white rice", "chicken"]]
    with pytest.raises(SystemExit, match="wine"):
        bex.build_external_co_stats(
            corpus, json.loads(INGREDIENT_MAPPING.read_text()), _class_mapping(),
            ingredient_mapping_sha256="0" * 64,
        )


# ── CLI round-trip: the emitted file passes the trainer's fail-fast loader ──────

def test_cli_output_round_trips_through_load_co_stats(tmp_path):
    out = tmp_path / "co_stats.json"
    rc = bex.main(["--corpus", str(FIXTURE_CORPUS), "--out", str(out)])
    assert rc == 0
    loaded = loss_config.load_co_stats(
        out, split_seed=None,
        class_mapping_sha256=lineage.file_sha256(CLASS_MAPPING),
    )
    assert loaded["source"] == "recipe1m"


# ── loss_config acceptance matrix (null split_seed only when external) ──────────

def _stats(source=None, split_seed=42, mapping_sha="ab" * 32):
    stats = {
        "schema": "co_stats.v2",
        "split_seed": split_seed,
        "class_mapping_sha256": mapping_sha,
        "channel_count": 6,
        "special_channel_indices": [5],
        "train_images": 3,
        "pixel_counts": {"train": [0] * 6},
        "presence_counts": [0] * 6,
        "joint_presence_counts": [[0] * 6 for _ in range(6)],
    }
    if source is not None:
        stats["source"] = source
        # External files must carry their derivation provenance; the rejection
        # tests below strip these to prove they are required.
        stats["ingredient_mapping_sha256"] = "ef" * 32
        stats["palette_coverage"] = {"with_statistics": [],
                                     "without_statistics": []}
    return stats


def _write(tmp_path, stats):
    path = tmp_path / "co_stats.json"
    path.write_text(json.dumps(stats))
    return path


def test_external_source_accepts_a_null_seed(tmp_path):
    path = _write(tmp_path, _stats(source="recipe1m", split_seed=None))
    loaded = loss_config.load_co_stats(path, split_seed=None,
                                       class_mapping_sha256="ab" * 32)
    assert loaded["source"] == "recipe1m"


def test_external_source_ignores_the_invocation_seed(tmp_path):
    # Corpus statistics are split-independent; a --split-seed on the invocation
    # (recorded in lineage for the dataset) is not a mismatch.
    path = _write(tmp_path, _stats(source="recipe1m", split_seed=None))
    loaded = loss_config.load_co_stats(path, split_seed=42,
                                       class_mapping_sha256="ab" * 32)
    assert loaded["split_seed"] is None


def test_external_source_with_a_stamped_seed_is_rejected(tmp_path):
    path = _write(tmp_path, _stats(source="recipe1m", split_seed=42))
    with pytest.raises(SystemExit, match="split_seed"):
        loss_config.load_co_stats(path, split_seed=42,
                                  class_mapping_sha256="ab" * 32)


def test_internal_stats_still_require_the_seed(tmp_path):
    # The pre-existing fail-fast contract is untouched for split-derived stats.
    path = _write(tmp_path, _stats(split_seed=42))
    with pytest.raises(SystemExit, match="--split-seed"):
        loss_config.load_co_stats(path, split_seed=None,
                                  class_mapping_sha256="ab" * 32)


def test_unknown_source_is_rejected(tmp_path):
    path = _write(tmp_path, _stats(source="scraped_blog", split_seed=None))
    with pytest.raises(SystemExit, match="scraped_blog"):
        loss_config.load_co_stats(path, split_seed=None,
                                  class_mapping_sha256="ab" * 32)


def test_external_source_still_enforces_palette_identity(tmp_path):
    # class_mapping_sha256 pins PALETTE identity, not derivation input — the
    # external build never reads the FoodSeg103 mapping but must stamp the
    # same palette hash.
    path = _write(tmp_path, _stats(source="recipe1m", split_seed=None))
    with pytest.raises(SystemExit, match="class mapping SHA-256"):
        loss_config.load_co_stats(path, split_seed=None,
                                  class_mapping_sha256="cd" * 32)


def test_external_source_missing_ingredient_mapping_sha_is_rejected(tmp_path):
    stats = _stats(source="recipe1m", split_seed=None)
    del stats["ingredient_mapping_sha256"]
    path = _write(tmp_path, stats)
    with pytest.raises(SystemExit, match="ingredient_mapping_sha256"):
        loss_config.load_co_stats(path, split_seed=None,
                                  class_mapping_sha256="ab" * 32)


def test_external_source_null_palette_coverage_is_rejected(tmp_path):
    # An explicit null is as untraceable as an absent key.
    stats = _stats(source="recipe1m", split_seed=None)
    stats["palette_coverage"] = None
    path = _write(tmp_path, stats)
    with pytest.raises(SystemExit, match="palette_coverage"):
        loss_config.load_co_stats(path, split_seed=None,
                                  class_mapping_sha256="ab" * 32)


def test_external_source_still_rejects_the_v1_schema(tmp_path):
    stats = _stats(source="recipe1m", split_seed=None)
    stats["schema"] = "co_stats.v1"
    path = _write(tmp_path, stats)
    with pytest.raises(SystemExit, match=r"co_stats\.v1"):
        loss_config.load_co_stats(path, split_seed=None,
                                  class_mapping_sha256="ab" * 32)


# ── Lineage records source + mapping SHA + coverage ─────────────────────────────

def test_train_extracts_co_stats_provenance_for_external_stats():
    stats = _stats(source="recipe1m", split_seed=None)
    stats["ingredient_mapping_sha256"] = "ef" * 32
    stats["palette_coverage"] = {"with_statistics": ["white_rice"],
                                 "without_statistics": []}
    prov = train._co_stats_provenance(stats)
    assert prov == {
        "source": "recipe1m",
        "ingredient_mapping_sha256": "ef" * 32,
        "palette_coverage": {"with_statistics": ["white_rice"],
                             "without_statistics": []},
    }
    # Internal (split-derived) stats record no provenance object — the
    # historical lineage shape is unchanged.
    assert train._co_stats_provenance(_stats(split_seed=42)) is None
    assert train._co_stats_provenance(None) is None


def test_build_lineage_carries_co_stats_provenance(tmp_path):
    checkpoint = tmp_path / "checkpoint.pt"
    checkpoint.write_bytes(b"fake checkpoint bytes")
    prov = {"source": "recipe1m", "ingredient_mapping_sha256": "ef" * 32,
            "palette_coverage": {"with_statistics": [], "without_statistics": []}}
    manifest = lineage.build_lineage(
        checkpoint, train_config={}, co_stats_provenance=prov,
    )
    assert manifest["co_stats_provenance"] == prov
    # Absent → explicit null, like pretrained_checkpoint / co_stats_sha256.
    assert lineage.build_lineage(checkpoint, train_config={})[
        "co_stats_provenance"] is None


def test_preserve_metrics_carries_provenance_across_reexport(tmp_path):
    checkpoint = tmp_path / "checkpoint.pt"
    checkpoint.write_bytes(b"fake checkpoint bytes")
    prov = {"source": "recipe1m", "ingredient_mapping_sha256": "ef" * 32,
            "palette_coverage": {"with_statistics": [], "without_statistics": []}}
    first = lineage.build_lineage(checkpoint, train_config={},
                                  co_stats_provenance=prov)
    path = tmp_path / "lineage.json"
    lineage.write_lineage(first, path)
    # A re-export of the SAME checkpoint (emit_lineage rebuilds with nulls)
    # must not wipe the recorded provenance.
    second = lineage.build_lineage(checkpoint, train_config={})
    lineage.preserve_metrics(second, path)
    assert second["co_stats_provenance"] == prov


# ── CLI surface on train.py ─────────────────────────────────────────────────────

def test_train_help_lists_co_stats_override(capsys):
    with pytest.raises(SystemExit) as excinfo:
        train.main(["--help"])
    assert excinfo.value.code == 0
    assert "--co-stats" in capsys.readouterr().out

"""Export-gate tests (model-production task 6, Req 4.2–4.5).

These exercise the pure, torch/coremltools-free gate predicates against a fixed
reference set. The full per-pixel oracle run against a real checkpoint.pt is gated
on the GPU training prerequisite (stage 3) and is NOT run here — only the decision
logic that decides export eligibility.
"""

import json

import numpy as np
import pytest

import export


# The authoritative palette order (mirrors the ClassPalette standard palette:
# 25 solids with cereal appended at index 24, liquids at 25–32, sentinels at
# 33/34/35 — myfoodrepo-bridge PRD). The gate reads this from
# class_mapping_foodseg103.json; locking it here guards against a silent
# reorder of the mapping file (Req 4.4 "in palette order").
EXPECTED_PALETTE = [
    "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
    "potato_boiled", "potato_mashed", "chips_fries", "chicken", "beef",
    "pork", "fish_white", "egg", "cheese", "salad_leaves",
    "broccoli", "carrot", "peas", "beans_baked", "lentils",
    "apple", "banana", "tomato", "mixed_vegetables",
    "cereal",
    "water", "coffee", "tea", "milk",
    "fruit_juice", "soup", "beer", "wine",
    "background", "unknown_food", "unsupported_liquid",
]

# The committed mapping file is regenerated to the v2 order by the dataset-bridge
# context (myfoodrepo-bridge tasks); until that lands this worktree still carries
# the 35-channel v1 file, so the committed-file lock below is integration-gated
# and activates automatically once channel_count reads 36.
_COMMITTED_MAPPING_IS_V2 = (
    json.loads(export._MAPPING_PATH.read_text()).get("channel_count") == 36
)


# ── Channel count / palette order (Req 4.4) ─────────────────────────────────────

def test_expected_palette_is_36_channel_v2():
    assert len(EXPECTED_PALETTE) == export.EXPECTED_CHANNEL_COUNT == 36
    assert EXPECTED_PALETTE[24] == "cereal"
    assert EXPECTED_PALETTE[25:33] == [
        "water", "coffee", "tea", "milk", "fruit_juice", "soup", "beer", "wine",
    ]
    assert EXPECTED_PALETTE[33:] == [
        "background", "unknown_food", "unsupported_liquid",
    ]


@pytest.mark.skipif(
    not _COMMITTED_MAPPING_IS_V2,
    reason="class_mapping_foodseg103.json still v1/35-channel — the "
           "dataset-bridge context regenerates it to v2; lock activates on "
           "integration",
)
def test_palette_channel_names_match_v2_order():
    assert export.palette_channel_names() == EXPECTED_PALETTE


def test_validate_channel_count_accepts_36():
    export.validate_channel_count(36)  # no raise


@pytest.mark.parametrize("n", [0, 27, 35, 37, 103])
def test_validate_channel_count_rejects_non_36(n):
    with pytest.raises(export.ExportGateError):
        export.validate_channel_count(n)


# ── Weight budget (Req 4.2) ─────────────────────────────────────────────────────

def _make_mlpackage(tmp_path, total_bytes):
    pkg = tmp_path / "segmenter.mlpackage"
    (pkg / "Data").mkdir(parents=True)
    (pkg / "Data" / "weights.bin").write_bytes(b"\0" * total_bytes)
    (pkg / "Manifest.json").write_text("{}")
    return pkg


def test_mlpackage_weight_bytes_sums_recursively(tmp_path):
    pkg = _make_mlpackage(tmp_path, total_bytes=1000)
    # weights.bin (1000) + Manifest.json (2 bytes "{}")
    assert export.mlpackage_weight_bytes(str(pkg)) == 1002


def test_validate_weight_budget_under_passes(tmp_path):
    pkg = _make_mlpackage(tmp_path, total_bytes=1024)
    assert export.validate_weight_budget(str(pkg)) == 1024 + 2


def test_validate_weight_budget_over_fails(tmp_path):
    pkg = _make_mlpackage(tmp_path, total_bytes=10)
    with pytest.raises(export.ExportGateError):
        export.validate_weight_budget(str(pkg), max_bytes=5)


def test_validate_weight_budget_missing_path_fails(tmp_path):
    with pytest.raises(export.ExportGateError):
        export.mlpackage_weight_bytes(str(tmp_path / "nope.mlpackage"))


# ── Preprocessing parity (Req 4.5) ──────────────────────────────────────────────

MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


def test_preprocess_square_input_normalises_no_pad():
    t = 8
    rgb = np.full((t, t, 3), 0.5, dtype=np.float32)
    out = export.preprocess_reference(rgb, t)
    assert out.shape == (t, t, 3)
    expected = (0.5 - MEAN) / STD
    np.testing.assert_allclose(out[0, 0], expected, rtol=1e-5)
    # No padding for a square input: every pixel equals the normalised value.
    np.testing.assert_allclose(out, np.broadcast_to(expected, out.shape), rtol=1e-5)


def test_preprocess_non_square_pads_with_normalised_zero():
    t = 8
    # Tall portrait (t × t/2): letterbox keeps the left t/2 columns, pads the rest.
    rgb = np.full((t, t // 2, 3), 0.5, dtype=np.float32)
    out = export.preprocess_reference(rgb, t)
    assert out.shape == (t, t, 3)
    pad = (0.0 - MEAN) / STD
    content = (0.5 - MEAN) / STD
    np.testing.assert_allclose(out[0, 0], content, rtol=1e-5)        # content region
    np.testing.assert_allclose(out[0, t - 1], pad, rtol=1e-5)        # padded region
    # The pad value is the network's view of pure black — distinct from content.
    assert not np.allclose(pad, content)


def test_resize_bilinear_identity_when_same_size():
    img = np.random.default_rng(1).random((5, 7, 3), dtype=np.float32)
    np.testing.assert_array_equal(export._resize_bilinear(img, 5, 7), img)


def test_resize_bilinear_changes_dims():
    img = np.zeros((2, 2, 3), dtype=np.float32)
    out = export._resize_bilinear(img, 4, 4)
    assert out.shape == (4, 4, 3)


# ── Equivalence oracle (Req 4.3) ────────────────────────────────────────────────

def _logits(seed=0, shape=(36, 8, 8)):
    return np.random.default_rng(seed).standard_normal(shape).astype(np.float32)


def test_oracle_identical_passes():
    a = _logits()
    err, agree, ok = export.oracle_agreement(a, a.copy())
    assert err == 0.0 and agree == 1.0 and ok


def test_oracle_large_logit_error_fails():
    a = _logits()
    b = a + 0.6  # exceeds ORACLE_MAX_ABS_ERR (0.5, Decision 14); argmax unchanged
    err, agree, ok = export.oracle_agreement(a, b)
    assert err >= export.ORACLE_MAX_ABS_ERR
    assert agree == 1.0          # uniform shift keeps argmax
    assert not ok                # but the logit-error gate fails it


def test_oracle_argmax_disagreement_fails():
    a = _logits(seed=1)
    b = _logits(seed=2)  # unrelated → argmax agreement well below 99%
    _, agree, ok = export.oracle_agreement(a, b)
    assert agree < export.ORACLE_ARGMAX_MIN
    assert not ok


def test_oracle_shape_mismatch_fails():
    err, agree, ok = export.oracle_agreement(_logits(shape=(36, 8, 8)),
                                             _logits(shape=(36, 4, 4)))
    assert err == float("inf") and agree == 0.0 and not ok


# ── Metadata stamp contract (Req 5.4) ───────────────────────────────────────────

def test_model_version_metadata_key_matches_swift_contract():
    # Must equal CoreMLInferenceEngine.modelVersionMetadataKey in Swift.
    assert export.MODEL_VERSION_METADATA_KEY == "medata.modelVersion"


def test_model_version_from_lineage_reads_join_key(tmp_path):
    lineage = tmp_path / "lineage.json"
    lineage.write_text(json.dumps({"model_version": "abc123def456", "checkpoint_sha256": "x"}))
    assert export.model_version_from_lineage(str(lineage)) == "abc123def456"

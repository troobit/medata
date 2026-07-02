"""Tests for checkpoint-mode plate routing (Req 3.7 / 4.7, tasks 7-8).

The liquid check runs FIRST: a plate whose liquid-mapped mass fraction is
>= 0.05 is always stamped mixture, never single_dominant. tau_route = 0.90
applies to the dominant mapped solid class's mass fraction of TOTAL plate
mass (unmapped included). With --checkpoint, single-dominant plates carry
real segmenter probabilities + the real checkpoint SHA; the segmenter itself
is monkeypatched here (torch stays out of the test environment) — parity
with make_fixtures.py is via the export.load_checkpoint / reference_input
seam, exercised in the real (task 39) run.
"""

import hashlib
import json
from pathlib import Path

import numpy as np
import pytest

import ingest
import mapping
from n5k_testkit import make_n5k_tree, make_test_mapping_artifact

from test_ingest import load_fixture, load_summary


def _record(ingredients):
    return ingest.DishRecord(
        dish_id="dish_t", total_carbs_g=1.0, total_protein_g=1.0,
        total_fat_g=1.0, ingredients=ingredients)


@pytest.fixture(scope="module")
def palette():
    return mapping.parse_palette()


@pytest.fixture(scope="module")
def plate_mapping(tmp_path_factory, palette):
    # white_rice / broccoli mapped, soup liquid-mapped, soy sauce unmapped —
    # enough shape for every routing branch.
    root = tmp_path_factory.mktemp("map") / "data"
    make_n5k_tree(root, {"dish_seed": {}})
    artifact = make_test_mapping_artifact(
        tmp_path_factory.mktemp("map2") / "mapping.json", root)
    return mapping.load_mapping(
        artifact,
        expected_palette_class_list=palette.class_list,
        expected_metadata_version=json.loads(
            artifact.read_text())["n5k_metadata_version"],
    )


def _route(ingredients, plate_mapping, palette, checkpoint=True):
    info = ingest.route_info(_record(ingredients), plate_mapping, palette)
    return info, ingest.decide_estimator_path(
        info, checkpoint_available=checkpoint)


RICE = "ingr_0000000026"
BROCCOLI = "ingr_0000000027"
SOUP = "ingr_0000000326"
SOY = "ingr_0000000508"


# --------------------------------------------------------------------------- #
# Routing decision (pure).
# --------------------------------------------------------------------------- #
class TestRoutingDecision:
    def test_without_checkpoint_everything_is_mixture(self, plate_mapping,
                                                       palette):
        _, path = _route([(RICE, "white rice", 200.0)], plate_mapping,
                         palette, checkpoint=False)
        assert path == ingest.ESTIMATOR_MIXTURE

    def test_dominant_at_tau_route_is_single_dominant(self, plate_mapping,
                                                      palette):
        # Exactly 0.90 of total mass clears the >= threshold.
        _, path = _route([(RICE, "white rice", 90.0), (SOY, "soy sauce", 10.0)],
                         plate_mapping, palette)
        assert path == ingest.ESTIMATOR_SINGLE_DOMINANT

    def test_unmapped_heavy_plate_cannot_be_single_dominant(self, plate_mapping,
                                                            palette):
        # Fraction is of TOTAL plate mass, unmapped included.
        _, path = _route([(RICE, "white rice", 85.0), (SOY, "soy sauce", 15.0)],
                         plate_mapping, palette)
        assert path == ingest.ESTIMATOR_MIXTURE

    def test_liquid_check_runs_first(self, plate_mapping, palette):
        # Rice clears tau_route exactly, but 5% liquid-mapped mass forces
        # mixture — the liquid check precedes the dominance check (Req 4.7).
        info, path = _route(
            [(RICE, "white rice", 90.0), (SOUP, "chicken soup", 5.0),
             (SOY, "soy sauce", 5.0)],
            plate_mapping, palette)
        assert info.dominant_fraction == pytest.approx(0.90)
        assert info.liquid_fraction == pytest.approx(0.05)
        assert path == ingest.ESTIMATOR_MIXTURE

    def test_liquid_below_significant_fraction_does_not_route(self,
                                                              plate_mapping,
                                                              palette):
        _, path = _route(
            [(RICE, "white rice", 95.0), (SOUP, "chicken soup", 4.0),
             (SOY, "soy sauce", 1.0)],
            plate_mapping, palette)
        assert path == ingest.ESTIMATOR_SINGLE_DOMINANT

    def test_dominance_is_per_class_aggregate_of_solids_only(self,
                                                             plate_mapping,
                                                             palette):
        # Two rice rows aggregate to one class; a liquid class can never be
        # the dominant class even when its mass dominates.
        info, _ = _route(
            [(RICE, "white rice", 50.0), (RICE, "white rice", 45.0),
             (BROCCOLI, "broccoli", 5.0)],
            plate_mapping, palette)
        assert info.dominant_class == "white_rice"
        assert info.dominant_fraction == pytest.approx(0.95)


# --------------------------------------------------------------------------- #
# Checkpoint-mode CLI (--checkpoint; segmenter monkeypatched).
# --------------------------------------------------------------------------- #
NUM_CLASSES = 35        # 24 solids + 8 liquids + 3 sentinels
TARGET_SIZE = 513


@pytest.fixture()
def checkpoint_run(tmp_path, monkeypatch):
    root = make_n5k_tree(tmp_path / "data", {
        # 95% rice -> single_dominant.
        "dish_dom": {"ingredients": [(26, 190.0), (508, 10.0)]},
        # rice + broccoli 60/40 -> mixture.
        "dish_mix": {"ingredients": [(26, 120.0), (27, 80.0)]},
        # dominant rice but significant soup -> mixture (liquid first).
        "dish_soup": {"ingredients": [(26, 180.0), (326, 20.0)]},
    })
    artifact = make_test_mapping_artifact(tmp_path / "mapping.json", root)
    ckpt = tmp_path / "checkpoint.pt"
    ckpt.write_bytes(b"fake-checkpoint-bytes")

    monkeypatch.setattr(ingest, "_load_segmenter",
                        lambda checkpoint_path, num_classes: "fake-model")

    def fake_run(model, rgb_path, num_classes):
        assert model == "fake-model"
        assert Path(rgb_path).is_file()
        probs = np.zeros((TARGET_SIZE, TARGET_SIZE, num_classes),
                         dtype=np.float32)
        probs[..., 0] = 1.0
        return probs

    monkeypatch.setattr(ingest, "_run_segmenter", fake_run)

    out = tmp_path / "out"
    rc = ingest.main([
        "--n5k-dir", str(root), "--out", str(out),
        "--mapping", str(artifact), "--download-date", "2026-07-02",
        "--checkpoint", str(ckpt),
    ])
    assert rc == 0
    return out, ckpt


class TestCheckpointMode:
    def test_single_dominant_carries_probs_and_real_sha(self, checkpoint_run):
        out, ckpt = checkpoint_run
        fx = load_fixture(out, "dish_dom")
        assert fx.estimator_path == "single_dominant"
        assert fx.segmenter_checkpoint_sha256 == hashlib.sha256(
            ckpt.read_bytes()).hexdigest()
        # FP16 LE [H, W, C] probability tensor; no ground-truth argmax exists
        # for N5k (the purity gate derives argmax from the probs, Req 4.2).
        assert len(fx.nadir_probs) == TARGET_SIZE * TARGET_SIZE * NUM_CLASSES * 2
        assert len(fx.nadir_argmax) == 0
        # Geometry stays the pinned camera model, not the tensor size.
        assert fx.nadir_intrinsics.image_width == 640
        assert fx.nadir_intrinsics.image_height == 480

    def test_mixture_keeps_sentinel_and_no_probs(self, checkpoint_run):
        out, _ = checkpoint_run
        for dish in ("dish_mix", "dish_soup"):
            fx = load_fixture(out, dish)
            assert fx.estimator_path == "mixture"
            assert fx.segmenter_checkpoint_sha256 == ingest.SENTINEL_SHA
            assert len(fx.nadir_probs) == 0

    def test_exactly_one_fixture_per_plate(self, checkpoint_run):
        out, _ = checkpoint_run
        fixtures = sorted(p.name for p in out.glob("*.fixture"))
        assert fixtures == ["dish_dom.fixture", "dish_mix.fixture",
                            "dish_soup.fixture"]
        summary = load_summary(out)
        assert summary["ingested"] == 3
        assert summary["estimator_paths"] == {"mixture": 2,
                                              "single_dominant": 1}

    def test_liquid_exclusion_recorded_in_summary(self, checkpoint_run):
        out, _ = checkpoint_run
        summary = load_summary(out)
        assert summary["liquid_excluded"] == ["dish_soup"]

    def test_missing_checkpoint_file_fails_loudly(self, tmp_path):
        root = make_n5k_tree(tmp_path / "data", {"dish_1": {}})
        artifact = make_test_mapping_artifact(tmp_path / "mapping.json", root)
        missing = tmp_path / "nope.pt"
        with pytest.raises(SystemExit) as exc:
            ingest.main([
                "--n5k-dir", str(root), "--out", str(tmp_path / "out"),
                "--mapping", str(artifact), "--checkpoint", str(missing),
            ])
        assert str(missing) in str(exc.value)
